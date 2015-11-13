package Plot::PlotGG;
use Exporter;
use Statistics::R;
use Carp;

use Data::Dumper;
@ISA = qw /Exporter/;
@EXPORT= qw /plot_tiles_by_index plot_linegraph_by_indices plot_stack_bg_hash_by_indices plot_violin_by_matrix plot_stack_bg_by_matrix/;

=pod

=head1 NAME
Plots

=head1 VERSION
0.1

=head1 SYNOPSIS
A series of functions that call and create common plots using the R Statistics
Framework and the ggplot2 library.

Depends on R::Statistics from CPAN and ggplot2 from CRAN


=head1 FUNCTIONS

=cut


sub plot_linegraph_by_indices {
=pod

=head2 plot_linegraph

using GGPLOT2, plots a series of lines,

	plot_linegraph_by_indices({
		data => {
			'a' => [2,4,6,8],
			'b' => [1,2,3,4]
			},
		xlab => 'position',
		ylab=> 'quality',
		label => 'sample',
		output_file => 'test',
		});

Takes a hash of array refs where the key is the identifier
for that data set and the array is the data to be plotted.

xlab,ylab,label, and output_file are all optional and will
set to the following default values: xaxis , yaxis,labels,graph.ps.

=cut

#get our data or default/croak.

	my $params = shift // croak "You passed nothing";
	my $data = $params->{data} // croak "need data man";
	my $output_file = "$params->{output_file}.pdf" // 'graph.ps';
	my $x_label = $params->{xlab} // 'xaxis';
	my $y_label = $params->{ylab} // 'yaxis';
	my $labels = $params->{label} // 'labels';

	unless ($params->{force}){
		return if (-f $output_file);
		}
#make our bridge
	my $R = new Statistics::R;
#load
	$R->run('library(ggplot2)');
#set output
	$R->run(qq`pdf("$output_file")`);


#get our data hash prepared
	my $data_hash = {
		x_axis=> [],
		y_axis=> [],
		label =>[],
		} ;


#unravel to a dataframe
	map {
		#set our label, get our array
		my $label = $_;
		my $data_array = $data->{$_};
		
		#unravel , pushing a label ID everytime we push a datavalue
		map {
			push $data_hash->{label} , $label;
			push $data_hash->{y_axis}, $data_array->[$_];
			push $data_hash->{x_axis}, $_;
			}(0..$#{$data_array});
		
		}keys %{$data};


#data_frame_statement (name = c(numbers) or c("text"));
	my $data_frame = "labels = c(\"". join('","',@{$data_hash->{label}})."\"),";
	$data_frame .=	 "x_label = factor(c(".join(',',@{$data_hash->{x_axis}}).")),";
	$data_frame .=	 "y_label = c(".join(',',@{$data_hash->{y_axis}}).")";
#load
	$R->run("df <- data.frame($data_frame)");
#plot
	$R->run("ggplot(df, aes (x = x_label, y=y_label,color = labels,group = labels))+ geom_point(alpha=0.5)+geom_line(alpha=0.5) +theme(axis.text.x = element_text(size=4,angle=90),plot.background = element_blank(),panel.grid.major = element_blank(),panel.grid.minor = element_blank(),panel.background = theme_blank())+ ggtitle(\"$params->{title}\")+xlab(\"$params->{xlab}\")+ylab(\"$params->{ylab}\") + labs(color = \"$params->{label}\")");

	if ($params->{history}){
		my $text = "library(ggplot2)\npostscript(\"$output_file\", horizontal=FALSE, width=500, height=500)\n";
		$text.="df <- data.frame($data_frame)\nggplot(df, aes (x = $x_label, y=$y_label,color = $labels,group = $labels))+ geom_point()+geom_line() +theme(axis.text.x = element_text(size=4,angle=90),plot.background = element_blank(),panel.grid.major = element_blank(),panel.grid.minor = element_blank(),panel.background = theme_blank())+ ggtitle(\"$params->{title}\")\n";
		print_R_script("$params->{output_file}.R","$text");
	}
#fin
}

sub plot_stack_bg_hash_by_indices
{
=pod 

=head2 plot_stacked_bg_by_indices

using GGPLOT2 plots a series of stacked bargraphs

	plot_stack_bg_hash_by_indices({
	data => {
			'a' => [2,4,6,8],
			'b' => [1,2,3,4]
			},
	enum => [qw/A T G C/],
	xlab => 'position',
	ylab=> 'quality',
	label => 'sample',
	output_file => 'stacked_bg_by_indices_test'
	});


=cut
	#get our data or default/croak.


	my $params = shift // croak "You passed nothing";
	my $data = $params->{data} // croak "need data man";
	my $enum = $params->{enum} // croak "need an enum to use this function"; $enum ={};
	#unroll to lookup hash , enum_value => index
	map {$enum->{$_} = $params->{enum}->[$_]} (0..$#{$params->{enum}}); 

	my $output_file = "$params->{output_file}.pdf" // 'graph.ps';
	my $val_lab = $params->{val_lab} // 'value_label';
	my $enum_lab = $params->{enum_lab} // 'enum_lab';
	my $labels = $params->{label} // 'labels';

	unless ($params->{force}){
		return if (-f $output_file);
		}
#make our bridge
	my $R = new Statistics::R;
#load
	$R->run('library(ggplot2)');
#set output
	$R->run(qq`pdf("$output_file")`);


#get our data hash prepared
	my $data_hash = {
		value=>[],
		enum =>[],
		label =>[],
		} ;

#Unroll into a proper datastructure

	map{
		#set outer loop variables
		my $label = $_;
		my $array = $data->{$_};
		map{
			#push , value , enum label , sample label for each value
			push $data_hash->{value},$array->[$_];
			push $data_hash->{enum},$enum->{$_};
			push $data_hash->{label}, $label;
			}(0..$#{$array});
		}keys %{$data};

#create data frame statement
my $data_frame = "labels = c(\"". join('","',@{$data_hash->{label}})."\"),";
$data_frame .=	 "enum_lab = c(\"". join('","',@{$data_hash->{enum}})."\"),";
$data_frame .= 	 "val_lab = c(".join(',',@{$data_hash->{value}}).")";

#load
	$R->run("df <- data.frame($data_frame)");
#plot
	$R->run("ggplot(df, aes (x = labels, y=val_lab ,fill = enum_lab))  +geom_bar(stat=\"identity\") + ggtitle(\"$params->{title}\") +xlab(\"$params->{x_label}\")+labs(fill = \"$params->{enum_lab}\")+ylab(\"$params->{y_label}\")"); 
	
#fin
	if ($params->{history}){
		my $text = "library(ggplot2)\npostscript(\"$output_file\", horizontal=FALSE, width=500, height=500)\n";
		$text.="df <- data.frame($data_frame)\nggplot(df, aes (x = $labels, y=$val_lab ,fill = $enum_lab))  +geom_bar(stat=\"identity\") + ggtitle(\"$params->{title}\")\n";
		print_R_script("$params->{output_file}.R","$text");
	}
}
	
sub plot_violin_by_matrix{
=pod

plot_violin_by_matrix({data => {
			'a' => [[0,1,2,1,3,5],[1,2,3,1,10],[0,1,2,1,3,5],[0,1,2,1,3,5]],
			'b' => [[0,1,5,7,8],[8,5,3,5,0]]
			},
	xlab => 'position',
	ylab=> 'quality',
	label => 'sample',
	output_file => 'violin_by_indices_test',});

given a series of data in an array matrix format, plots violin plot

The X-labels will always be the outer index numbers, the y-values will always be the internal
number input the value of the x,y index. 

I.E
in a , the 0,0 index is 0. So 0 is put in 0 times 
the 1,0 index is 1. So 1 is put in 1 time
the 2,0 index is 2. So 2 is put in 2 times
the 3,4 index is 3. So 4 is put in 3 times etc.
=cut
	my $params = shift // croak "You passed nothing";
	my $data = $params->{data} // croak "need data man";
	my $output_file = "$params->{output_file}.pdf" // 'graph.ps';
	
	unless ($params->{force}){
		return if (-f $output_file);
		}

#make our bridge
	my $R = new Statistics::R;
#load
	$R->run('library(ggplot2)');
#set output
	$R->run(qq`pdf("$output_file")`);


#get our data hash prepared
	my $data_hash = {
		x_axis=> [],
		y_axis=> [],
		label =>[],
		y_value =>[]
		} ;


map{
	my $matrix = $data->{$_};
	my $label = $_;
	map {
		my $x = $_;
		my $y = $matrix->[$x];
		map{
			push $data_hash->{x_axis}, $x;
			push $data_hash->{y_axis}, $_;
			push $data_hash->{y_value},$y->[$_];
			push $data_hash->{label},$label;
			}(0..$#{$y});

		}(0..$#{$matrix});

	}keys %{$data};

#data_frame_statement (name = c(numbers) or c("text"));
	 my $data_frame = " labels  = c(\"". join('","',@{$data_hash->{label}})."\"),";
	 $data_frame.=    " x_label = factor (c(".join(',',@{$data_hash->{x_axis}}).")),";
	 $data_frame.=    " y_label = c(".join(',',@{$data_hash->{y_axis}})."),";
	 $data_frame.=	  " y_weights = c(".join (',',@{$data_hash->{y_value}}).")";
#load
	 $R->run("df <- data.frame($data_frame)");

	 $R->run("ggplot(df, aes(x= x_label,y=y_label,fill=labels, weight = y_weights))  + geom_violin(scale=\"count\",position=\"identity\",alpha=0.5,linetype=\"blank\") +theme(axis.text.x = element_text(size=4,angle=90),plot.background= element_blank(),panel.grid.major = element_blank(),panel.grid.minor = element_blank(),panel.background = theme_blank())+ ggtitle(\"$params->{title}\")+ xlab(\"$params->{x_label}\") + ylab(\"$params->{y_label}\") + labs(\"$params->{label}\")");
	
	if ($params->{history}){
		my $text = "library(ggplot2)\npostscript(\"$output_file\")\n";
		$text.="df <- data.frame($data_frame)\nggplot(df, aes(x= $x_label,y=$y_label,fill=$labels, weight = y_weights))  + geom_violin(scale=\"count\",position=\"identity\",alpha=0.5,linetype=\"blank\") +theme(axis.text.x = element_text(size=4,angle=90),plot.background = element_blank(),panel.grid.major = element_blank(),panel.grid.minor = element_blank(),panel.background = theme_blank())+ ggtitle(\"$params->{title}\")\n";
		print_R_script("$params->{output_file}.R","$text");
		}
	}

sub plot_stack_bg_by_matrix{
=pod 

=head2 plot_stack_bg_by_matrix()


Plots stacked bargraphs based off of matrix

=cut 
	my $params = shift // croak "You passed nothing";
	my $data = $params->{data} // croak "need data man";
	my $enum = $params->{enum} // croak "need an enum to use this function"; $enum ={};
	#unroll to lookup hash , enum_value => index
	map {$enum->{$_} = $params->{enum}->[$_]} (0..$#{$params->{enum}}); 

	my $output_file = "$params->{output_file}.pdf" // 'graph.ps';
	

	unless ($params->{force}){
		return if (-f $output_file);
		}


#get our data hash prepared
	my $data_hash = {
		x_axis=> [],
		value=> [],
		enum =>[],
		} ;

	map{
		my $matrix = $data->{$_};
		map{
			my $x = $_;
			my $row = $matrix->[$x];
			map {
				push $data_hash->{enum} , $enum->{$_};
				push $data_hash->{x_axis} , $x;
				push $data_hash->{value}, $row->[$_];
				}(0..$#{$row});
			}(0..$#{$matrix})
		}keys %{$data};

	#create data frame statement
	my $data_frame = "labels = factor(c(". join(',',@{$data_hash->{x_axis}}).")),";
	$data_frame.=	 "enum_lab = c(\"". join('","',@{$data_hash->{enum}})."\"),";
	$data_frame.=	 "val_lab = c(".join(',',@{$data_hash->{value}}).")";

#make our bridge
	my $R = new Statistics::R;
#load
	$R->run('library(ggplot2)');
#set output
	$R->run(qq`pdf("$output_file")`);
#load
	$R->run("df <- data.frame($data_frame)");
#plot
	$R->run("ggplot(df, aes (x = labels, y=val_lab ,fill = enum_lab)) + geom_bar(stat=\"identity\",linetype=\"blank\")+theme(axis.text.x = element_text(size=4,angle=90),plot.background = element_blank(),panel.grid.major = element_blank(),panel.grid.minor = element_blank(),panel.background = theme_blank()) + ggtitle(\"$params->{title}\") +xlab(\"$params->{x_label}\")+ylab(\"$params->{y_label}\")+labs(fill = \"$params->{enum_lab}\")");
	
#fin
	if ($params->{history}){
		my $text = "library(ggplot2)\npostscript(\"$output_file\", horizontal=FALSE, width=500, height=500)\n";
		$text.="df <- data.frame($data_frame)\nggplot(df, aes (x = $labels, y=$val_lab ,fill = $enum_lab)) + geom_bar(stat=\"identity\")+theme(axis.text.x = element_text(size=4,angle=90),plot.background = element_blank(),panel.grid.major = element_blank(),panel.grid.minor = element_blank(),panel.background = theme_blank())+ ggtitle(\"$params->{title}\")\n";
		print_R_script("$params->{output_file}.R","$text");
		}



	}

sub plot_tiles_by_index{
=pod

=head2 plot_tiles_by_index();

plot a ggplot tile plot of a matrix of data;
Currently ONLY takes one matrix at a time as it is unclear
that multiple matrices would be useful to visualize in a single 
plot


=cut
	my $params = shift // croak "You passed nothing";
	my $data = $params->{data} // croak "need data man";
	my $output_file = "$params->{output_file}.pdf" // 'graph.pdf';
	#unravel to data frame;
	unless ($params->{force}){
		return if (-f $output_file);
		}
	my $data_hash = {
		x_axis => [ ],
		y_axis => [ ],
		value => [ ]
		};

	map {
		my $x = $_;
		my $y = $data->[$x];
		map{
			push $data_hash->{x_axis}, $x;
			push $data_hash->{y_axis}, $_;
			push $data_hash->{value},$y->[$_];
			}(0..$#{$y});
		}(0..$#{$data});

	my $data_frame = "x_label = factor(c(". join ( ',' , @{$data_hash->{x_axis}}).")),";
	   $data_frame.= "y_label = factor(c(". join ( ',' , @{$data_hash->{y_axis}}).")),";
	   $data_frame.= "val_lab = c(" . join (',',@{$data_hash->{value}}).")";

#make our bridge
	my $R = new Statistics::R;
#load
	$R->run('library(ggplot2)');
#set output
	$R->run(qq`pdf("$output_file")`);
#load
	$R->run("df <- data.frame($data_frame)");
#plot
	$R->run("ggplot(df, aes(x = x_label, y = y_label)) + geom_tile(aes(fill = val_lab)) + scale_fill_gradient(low=\"steelblue\", high=\"white\")+theme(axis.text.x = element_text(size=4,angle=90),plot.background = element_blank(),panel.grid.major = element_blank(),panel.grid.minor = element_blank(),panel.background = theme_blank()) + ggtitle(\"$params->{title}\") + xlab(\"$params->{x_label}\")+ylab(\"$params->{y_label}\")+labs(fill = \"$params->{fill_label}\")");

}

1;


sub print_R_script{
	open (R , '>' , shift) || die "Can't open the file to write !";
	print R shift;	
	return;
	}
