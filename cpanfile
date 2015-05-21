requires 'perl', '5.008001';

requires("Excel::Writer::XLSX");
requires("File::Basename");
requires("File::Cat");
requires("File::Path");
requires("File::Slurp");
requires("File::Temp");
requires("Spreadsheet::XLSX");
requires("Text::CSV_XS");
requires("Text::Iconv");

on 'test' => sub {
    requires 'Test::More', '0.98';
};

