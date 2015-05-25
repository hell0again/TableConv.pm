package TableConv::CLI;
use strict;
use warnings;
use utf8;

use Encode;
use Excel::Writer::XLSX;
use File::Basename qw/dirname basename/;
use File::Cat;
use File::Path qw/mkpath/;
use File::Slurp;
use File::Temp qw/tempdir/;
use Getopt::Long;
use Spreadsheet::XLSX;
use Text::CSV_XS;
use Text::Iconv;

use constant { SUCCESS => 0, INFO => 1, WARN => 2, ERROR => 3 };

sub new {
	my ($class) = @_;
	return bless +{}, $class;
}
sub run {
	my ($self, @args) = @_;

	my @commands;
	my $p = Getopt::Long::Parser->new(
        # config => [ "posix_default", "no_ignore_case", "gnu_compat" ],
		config => [ "gnu_compat", "no_ignore_case", "pass_through" ],
	);
    $p->getoptionsfromarray(
        \@args,
        "h|help"    => sub { unshift @commands, 'help' },
        "v|version" => sub { unshift @commands, 'version' },
		#"verbose!"  => sub { $self->verbose($_[1]) },
    );
    push(@commands, @args);
	my $cmd = shift @commands || 'convert';
	my $code = try {
		#my $call = $self->can("cmd_$cmd") or die "no command";
		my $call = "cmd_$cmd";
		$self->$call(@commands);
		return 0;
	} catch {
		die $_;
	};
	return $code;
}
sub parse_options {
	my ($self, $args, @spec) = @_;
	my $p = Getopt::Long::Parser->new(
		config => [ "no_auto_abbrev", "no_ignore_case" ],
	);
	$p->getoptionsfromarray($args, @spec);
}
sub print {
	my ($self, $msg, $type) = shift;
	my $fh = $type && $type >= WARN ? *STDERR : *STDOUT;
	print {$fh} $msg;
}
sub cmd_help {
	my $self = shift;
	my $module = $_[0] ? ("TableConv::Doc::" . ucfirst $_[0]) : "TableConv.pm";
	system "perldoc", $module;
}
sub cmd_version {
	my $self = shift;
	$self->printf("tableconv $TableConv::VERSION\n");
}
sub cmd_usage {
	my $self = shift;
	$self->print(<<EOS);
Usage
  tableconv convert CSV_FILE >XLSX_FILE
  tableconv reverse XLSX_FILE >CSV_FILE
  tableconv reverse --file-format=unix XLSX_FILE >CSV_FILE
EOS
}
sub cmd_convert {
	my ($self, @args) = @_;
	$self->parse_options(
		\@args,
	);
	$self->{source} = shift @args;
	$self->conv_with_conflicted();
}
sub conv_with_conflicted {
	my ($self) = @_;
	my $csv = $self->{source};
	my $lines = File::Slurp::read_file($csv);
	my $blocks = _parse_hunks($lines);

	my $tmp_prefix = "tableconv_" . "XXXXXXXX";
	my $cleanup = 1;
	my $tmp_dir = tempdir($tmp_prefix, CLEANUP => $cleanup);
	my $tmp_path = File::Spec->catfile($tmp_dir, "temp");
	my $workbook = Excel::Writer::XLSX->new($tmp_path);
	my $worksheet = $workbook->add_worksheet();

	my $idx = 59;
	my $formats = +{
		red_light => $workbook->add_format(
			bg_color => $workbook->set_custom_color($idx--, 255, 238, 238), #ffdddd
		),
		red_dark => $workbook->add_format(
			bg_color => $workbook->set_custom_color($idx--, 249, 203, 203), #f8cdcd
		),
		green_light => $workbook->add_format(
			bg_color => $workbook->set_custom_color($idx--, 219, 255, 219), #dbffdb
		),
		green_dark => $workbook->add_format(
			bg_color => $workbook->set_custom_color($idx--, 193, 233, 193), #c1e9c1
		),
		blue_light => $workbook->add_format(
			bg_color => $workbook->set_custom_color($idx--, 193, 193, 233),
		),
		blue_dark => $workbook->add_format(
			bg_color => $workbook->set_custom_color($idx--, 184, 184, 240),
		),
		gray_dark => $workbook->add_format(
			bg_color => $workbook->set_custom_color($idx--, 124, 124, 124),
		),
		#text => $workbook->add_format(
		#	num_format => "@",
		#),
		#integer => $workbook->add_format(
		#	num_format => "",
		#),
		default => $workbook->add_format(),
	};

	my $rows;
	my $offset = 0;
	my $show_markers = 1;
	map {
		my $block = $_;
		if (exists $block->{text}) {
			$rows = $self->parse_csv($block->{text});
			$offset += _xlsx_with_format($worksheet, $rows, $formats->{default}, $offset);
		} elsif (exists $block->{hunk}) {
			if ($show_markers) {
				$rows = [["<<<<<<< " . $block->{hunk}{label1}]];
				$offset += _xlsx_with_format($worksheet, $rows, $formats->{red_dark}, $offset);
			}
			$rows = $self->parse_csv($block->{hunk}{body1});
			$offset += _xlsx_with_format($worksheet, $rows, $formats->{red_light}, $offset);
			if (exists $block->{hunk}{body2}) {
				if ($show_markers) {
					$rows = [["||||||| " . $block->{hunk}{label2}]];
					$offset += _xlsx_with_format($worksheet, $rows, $formats->{blue_dark}, $offset);
				}
				$rows = $self->parse_csv($block->{hunk}{body2});
				$offset += _xlsx_with_format($worksheet, $rows, $formats->{blue_light}, $offset);
			}
			if ($show_markers) {
				$rows = [["======="]];
				$offset += _xlsx_with_format($worksheet, $rows, $formats->{gray_dark}, $offset);
			}
			$rows = $self->parse_csv($block->{hunk}{body3});
			$offset += _xlsx_with_format($worksheet, $rows, $formats->{green_light}, $offset);
			if ($show_markers) {
				$rows = [[">>>>>>> " . $block->{hunk}{label3}]];
				$offset += _xlsx_with_format($worksheet, $rows, $formats->{green_dark}, $offset);
			}
		} else {
			die "ﾌｧ!?";
		}
	} @$blocks;

	$workbook->close();
	cat($tmp_path, \*STDOUT);
}
sub _parse_hunks {
	my ($str, $stack) = @_;
	$stack = [] if !$stack;
	my ($before, $hunk, $after) = _first_hunk($str);
	push @$stack, {text => $before} if $before ne "";
	return $stack if (!$hunk);
	push @$stack, {hunk => $hunk};
	return _parse_hunks($after, $stack);
}
## 最初のhunkを探す
# <<<<と>>>>の前後はbefore, afterに格納、hunkがない場合はundef
sub _first_hunk {
	my ($txt) = @_;
	my ($before, $hunk, $after);
	#$DB::single = 1;
	if ($txt =~ s/\n?<<<<<<<\s([^\n]*)\n?(.*?)\n=======\n?(.*?)\n>>>>>>>\s([^\n]*)\n?(.*)//s) {
		$hunk = +{
			label1 => $1,
			#body1 => $2,
			body3 => $3,
			label3 => $4,
		};
		$after = $5;
		my $next = $2;
		if ($next =~ s/\n\|\|\|\|\|\|\|\s([^\n]*)\n?(.*)//s) {
			$hunk->{label2} = $1;
			$hunk->{body2} = $2;
		}
		$hunk->{body1} = $next;
	}
	$before = $txt;
	return ($before, $hunk, $after);
}

sub parse_csv {
	my ($self, $source_lines) = @_;
	my $rows = [];
	my $csv = Text::CSV_XS->new({binary => 1, allow_whitespace => 1}); # eol => ??
	my @row_buff;
	my $len = undef;
	## FIXME: 元のテキストの改行コードを失っているので \n 決め打ちになってる。
	my @lines = split("\n", $source_lines);
	while (my $row = shift @lines) {
		push(@row_buff, $row);
		my $st = $csv->parse(join("\n", @row_buff));
		if ($st) {
			my @fields = $csv->fields();
			@fields = map { "". $_ } @fields;
			if (defined $len && $len != scalar @fields) {
				# die "column len mismatch";
			} else {
				$len = scalar @fields;
			}
			push(@$rows, \@fields);
			@row_buff = ();
		}
	}
	$rows;
}
sub _xlsx_with_format {
	my ($worksheet, $rows, $format, $row_offset) = @_;
	map {
		my $row_i = $_;
		my $row = $rows->[$row_i];
		map {
			my $col_i = $_;
			my $val = $row->[$col_i];
			## string only. what about "00"?
			#($val =~ /^\d+$/) ?
			#	$worksheet->write_number($row_offset + $row_i, $col_i, $val, $format):
			#	$worksheet->write_string($row_offset + $row_i, $col_i, $val, $format);
			$worksheet->write_string($row_offset + $row_i, $col_i, $val, $format);
		} 0 .. $#{$row};
	} 0 .. $#{$rows};
	return scalar @$rows;
}



sub cmd_reverse {
	my ($self, @args) = @_;
	$self->parse_options(
		\@args,
		"f|ff|file-format=s" => \my $file_format,
	);
	$self->{source} = shift @args;
	$self->{file_format} = $file_format;
	$self->reverse();
}
sub reverse {
	my ($self) = @_;
	my $xlsx = $self->{source};
	#my $excel = Spreadsheet::XLSX->new($xlsx, Text::Iconv->new('utf-8', "windows-1251"));
	my $excel = Spreadsheet::XLSX->new($xlsx);
	my $sheet = shift @{$excel->{Worksheet}};
	$sheet->{MaxRow} ||= $sheet->{MinRow};

	my $matrix = [];
	foreach my $row_i ($sheet->{MinRow} .. $sheet->{MaxRow}) {
		my @row;
		$sheet->{MaxCol} ||= $sheet->{MinCol};
		foreach my $col_i ($sheet->{MinCol} .. $sheet->{MaxCol}) {
			my $cell = $sheet->{Cells}[$row_i][$col_i];
			my $val = ($cell)? $cell->{Val}: "";
			$val =~ s/&lt;/</g;
			$val =~ s/&gt;/>/g;
			$val =~ s/&amp;/&/g;
			push @row, $val;
		}
		push @$matrix, \@row;
	}
	my $eol = ($self->{file_format} =~  /unix/i)? "\n":
		($self->{file_format} =~  /mac/i)? "\r":
		"\r\n";
	my $csv = Text::CSV_XS->new({binary => 1, allow_whitespace => 1, eol => $eol});
	print join "", map {
		my $r = $_;
		my $first = $r->[0];
		if ($first =~ /^[<>|=]{7}/) {
			$first . $eol;
		} else {
			$csv->combine(@$r);
			$csv->string();
		}
	} @$matrix;
}



1;
