# NAME

TableConv - Convert csv to xlsx. Also reverse converted xlsx to csv.

# SYNOPSIS

    # install
    > git clone ...
    > cpanm .

    # convert csv to xlsx
    > tableconv convert $CSV_FILE

    # reverse xlsx to csv
    > tableconv reverse $XLSX_FILE

# DESCRIPTION

TableConv is a command line tool to convert csv file to xlsx.

TableConv is focused to editing csv file more easily. Not only converting
csv to xlsx, TableConv can reverse convert xlsx to csv with
less destructive changes. "sample/001" describes what kinds of changes
will happen through convert and reverse convert process.

For an experimental feature, TableConv can handle conflicted csv, which contains
conflict hunks (markers such as '<<<<<<<', '|||||||', '=======', '>>>>>>>').
When conflicted csv is passed, each hunks are highlighted in xlsx, so you
may defeat the conflict more easily.

# LICENSE

Copyright (C) hell0again.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# AUTHOR

hell0again <hell00again@gmail.com>
