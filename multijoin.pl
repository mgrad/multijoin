#!/usr/bin/perl -w
use strict;
use warnings;
use Tie::IxHash;

# main repo
my %db; tie %db, "Tie::IxHash";
my %db_heads; tie %db_heads, "Tie::IxHash";

# ========================= load_db() ======================== #
# this loads data to %db
sub load_db {
    my $href = (shift);     # we can't derefence that - since it will make a local copy
    my $data_ref = (shift);
    my @key_idxs = sort {$b <=> $a} @_;
    my @key_headers;

    # remove (1st line) with headers from data 
    my @headers = split(/\s+/, (shift @{$data_ref}));
    # remove 2nd line from data
    # shift @{$data_ref};

    # headers - get header names for keys
    foreach my $k_idx (@key_idxs) { 
        unshift @key_headers, splice(@headers,$k_idx, 1); 
    }

    # process data
    foreach my $row (@$data_ref)   {
       my @keys;
       my @cols = split(/\s+/,$row); 

       # data - remove keys values (start from last one)
       foreach my $k_idx (@key_idxs) { 
           unshift @keys, splice(@cols, $k_idx, 1); 
       }

       # create record name
       my $rec = "\$href";
       foreach my $k (@keys) { 
           $rec = $rec . '->' . "{\"$k\"}";
       }

       # store val in a record
       for (my $i=0; $i<=$#headers; $i++) {
           my $val = $cols[$i] || "-";
           my $ev_code = q/push @{/ . $rec . '->' . "{\"$headers[$i]\"}}, " . q($val);
           # print "$ev_code\n";
           eval "$ev_code";
           # warn @_ if @_;
       }
    }

    # store headers with idx in a hash
    for (my $i=0; $i<=$#key_headers; $i++) {
        $db_heads{$key_headers[$i]} = "k$i";
    }
    for (my $i=0; $i<=$#headers; $i++) {
        $db_heads{$headers[$i]} = "c$i";
    }
}

# ========================= report() ======================== #
sub report {
    our $db_href = (shift);
    our @rep_cols = @_;
    our @rows;

    # check if all columns exists
    foreach my $rc (@rep_cols) {
        print STDERR "WARNING: Column $rc does not exists\n" if (not exists $db_heads{$rc});
    }

    # check how many keys are there 
    our $level = 0;
    foreach my $k (keys %db_heads) {
        if ($db_heads{$k} =~ /^k\d+/) {
            $level++
         }
    }
    # print "level of keys: $level\n";

    # build @rows 
    our @keys;
    our $level_idx = 0;
    sub build_rows  {
        my $href = (shift);

        # the @row building part - when visitor found proper place in a tree
        if ($level_idx == $level) {
            my @cols = ();
            my @multi_cols = ();

            # build single row
            foreach my $h (@rep_cols) {
                my $val = "";
                # if this is a key column get the value from @keys
                if (exists $db_heads{$h} && $db_heads{$h} =~ /^k(\d+)$/) {
                    $val = eval "\$keys[$1]";
                # if that's not column key look in data 
                } elsif (exists $href->{"$h"}) {
                    my $a_sz = scalar @{$href->{$h}};
                    if ($a_sz == 1) {
                        $val = $href->{$h}->[0]
                    } else {
                        $val = "ar:$a_sz";
                        my $col_idx = scalar @cols;
                        push @multi_cols, $h, $col_idx, $a_sz;
                    }
                # if there isn't such column at all
                } else {
                    $val = "-";
                }
                push @cols, $val;
            }

            # add to @rows
            if (scalar @multi_cols) {
                my $a_sz = $multi_cols[2];
                for (my $i=0; $i<$a_sz; $i++) {
                    for (my $j=0; $j< scalar @multi_cols; $j+=3) {
                        my ($col_name, $col_idx,$col_a_sz) = @multi_cols[$j..$j+3];
                        warn ("Multidimensional arrays have diff sizes") if ($col_a_sz != $a_sz);
                        my $aref = $href->{$col_name};
                        $cols[$col_idx] = $aref->[$i];
                    }
                    my @tmp = @cols;   # make a local copy
                    push @rows, \@tmp; # and store reference
                }
                @multi_cols=();

            } else {
                push @rows, \@cols;
            }
        }

        # the tree exploring part (visitor)
        foreach my $k (keys %$href) {
            push @keys, $k;
            # print "$level_idx: " . join (" / ", @keys) . "\n";

            if (ref($href->{$k}) eq "HASH") {
                # moving forward in branches till leaves
                $level_idx++;
                build_rows ($href->{$k}) if ($level_idx <= $level);
                # moving back to root
                $level_idx--;
            } 
            pop @keys;
        }
   }

    # recurrence needed to discover the tree
    build_rows($db_href);

    # find max length in cols
    my @col_sz;
    foreach my $h (@rep_cols) { push @col_sz, length $h; }
    foreach my $ar (@rows) {
        my $max_sz = 0;
        for (my $i=0; $i<scalar @{$ar}; $i++) {
           my $c_sz = length ($ar->[$i]);
           $col_sz[$i] = $c_sz if (not exists $col_sz[$i] or $c_sz > $col_sz[$i]);
        }
    }
    
    # build format string
    my $format;
    foreach my $f (@col_sz) {
        $format .= " %-" . $f. "s ";
    }
    $format .= "\n";

    # build header bar string
    my @header_bar;
    foreach my $f (@col_sz) {
        push @header_bar, "-"x$f;
    }
    # print data
    printf $format, @rep_cols;
    printf $format, @header_bar;
    foreach my $cols_ar (@rows) {
        printf $format, @$cols_ar;
    }
}
# ========================= main() ======================== #

if (scalar @ARGV == 0) {
    print STDERR <<END;
This tool creates a 2d table.
The table joins multiple files on the same columns (keys).

This is extended version of the "join" linux tool, which:
- supports multiple keys,
- supports multiple files,
- fillouts the gaps (creating a array with blanks)
- supports one level of intersect

usage: $0 File1 KeyList1, File2 KeyList2 .. ReportColNames
    -File            - file name 
    -KeyList         - numbers of cols used as a key
    -ReportColNames  - Column names used to create report

Example: $0 a.txt 0,1 b.txt 0,3 "Foo, Bar, A, B" 
END
    exit 1;
}

my $skip_lines = q('^$|^-|^#');

while ( scalar @ARGV  > 1) {
    my ($fname, $keys) = splice(@ARGV, 0, 2);
    my @data = `grep -Ev $skip_lines $fname`;
    my @keys = split(/,\s*/, $keys);
    &load_db(\%db, \@data, @keys);
}

my @rep_cols = split(/,\s*/, $ARGV[0]);
report(\%db, @rep_cols);
