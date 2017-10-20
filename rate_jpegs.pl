use strict;
use Data::Dumper;
use File::Find;
use File::Basename;
use Tk;
use Tk::JPEG;
use Tk::Pane;
use File::Spec::Functions;
use File::Touch;
use Image::ExifTool qw(:Public);
use Time::HiRes qw( time );

##########################################################
#  Tunables
my @exif_suffixes = ( ".jpg", ".jpeg", ".JPG", ".JPEG" );
my $WOW_TEXT = "[wow]";
my $MAINWINDOW_W = 1280;
my $MAINWINDOW_H = 640;
##########################################################


my $rate_path = shift(@ARGV);
chomp($rate_path);

my @files;

find(\&wanted, $rate_path);

sub wanted {
    my ($name,$path,$suffix) = fileparse($File::Find::name, @exif_suffixes);
    if ( grep {$_ eq $suffix} @exif_suffixes ) {
        push @files, canonpath($File::Find::name);
    }
}

print "Rating " . scalar(@files) . " files\n";

my $ii = 0; # image index

my $mw = new MainWindow;

my $scrolled = $mw->Scrolled( 'Pane', -scrollbars => 'osoe', -width => 1280, -height => 640)->pack( -expand => 1, -fill => 'both');

my $imagit = $scrolled->Label->pack( -expand => 1, -fill => 'both');

my( $xscroll, $yscroll ) = $scrolled->Subwidget( 'xscrollbar', 'yscrollbar' );

my( $last_x, $last_y );

my $img2;

$mw->bind('<KeyPress>' => \&keypress);

$imagit->bind( '<Button1-ButtonRelease>' => sub { undef $last_x } );
$imagit->bind( '<Button1-Motion>' => [ \&drag, Ev('X'), Ev('Y'), ] );

my $current_image;

sub drag
{
    my( $w, $x, $y ) = @_;
    if ( defined $last_x )
    {
        my( $dx, $dy ) = ( $x-$last_x, $y-$last_y );
        my( $xf1, $xf2 ) = $xscroll->get;
        my( $yf1, $yf2 ) = $yscroll->get;
        my( $iw, $ih ) = ( $img2->width, $img2->height );
        if ( $dx < 0 )
        {
            $scrolled->xview( moveto => $xf1-($dx/$iw) );
        }
        else
        {
            $scrolled->xview( moveto => $xf1-($xf2*$dx/$iw) );
        }
        if ( $dy < 0 )
        {
            $scrolled->yview( moveto => $yf1-($dy/$ih) );
        }
        else
        {
            $scrolled->yview( moveto => $yf1-($yf2*$dy/$ih) );
        }
    }
    ( $last_x, $last_y ) = ( $x, $y );
}

sub factor
{
    my( $n, $m ) = @_;
    ($n>$m) ? int($n/$m) : 1
}

sub min
{
    my( $n, $m ) = @_;
    $n < $m ? $n : $m
}
sub max
{
    my( $n, $m ) = @_;
    $n > $m ? $n : $m
}

sub show_image
{
    my ($start, $end);
    print "Showing Image $files[$ii]\n";

    $current_image = {};
    $current_image->{filename} = $files[$ii];
    $current_image->{exifTool} = new Image::ExifTool;
    $current_image->{exifTool}->Options(Unknown => 1);
    $current_image->{exifTool}->ExtractInfo($current_image->{filename})
        || die "Unable to read EXIF data from $current_image->{filename}: " .
                $current_image->{exifTool}->GetInfo('Error');

    $current_image->{Orientation} = $current_image->{exifTool}->GetValue("Orientation");
    $current_image->{Comment} = $current_image->{exifTool}->GetValue("Comment");
    $current_image->{Rating} = $current_image->{exifTool}->GetValue("Rating");

    my $window_title = "(" . ($ii + 1) . "/" . scalar(@files) . ") $current_image->{filename}";
    if (exists($current_image->{Rating})) {
        print "Rating: $current_image->{Rating}\n";
        $window_title .= " Rating $current_image->{Rating}";
    }
    if (exists($current_image->{Comment})) {
        print "Comment: $current_image->{Comment}\n";
        $window_title .= " $current_image->{Comment}";
    }
    $mw->configure( -title => $window_title );

    $start = time();
    my $img1 = $mw->Photo( 'fullscale',
        -format => 'jpeg',
        -file => $current_image->{filename},
    );
    $end = time();
    printf("Tk::Photo Create Operation time %.4f\n", $end - $start);
    
    print "Image width " . $img1->width . "\n";
    print "Image height " . $img1->height . "\n";
    print "Orientation: $current_image->{Orientation}\n";
    print "Scrolled width " . $scrolled->width . "\n";
    print "Scrolled height " . $scrolled->height . "\n";

    my $factor_width;
    my $factor_height;
    if ($current_image->{Orientation} eq "Rotate 90 CW") {
        $factor_width = factor( $img1->height, $scrolled->width );
        $factor_height = factor( $img1->width, $scrolled->height );
    } else {
        $factor_width = factor( $img1->width, $scrolled->width );
        $factor_height = factor( $img1->height, $scrolled->height );
    }
    my $factor = max( $factor_width, $factor_height );
    print "Factor width $factor_width\n";
    print "Factor height $factor_height\n";
    if ($current_image->{Orientation} eq "Rotate 180") {
        $factor = 0 - $factor;
    }
    print "Factor $factor\n";
    $start = time();
    $img2 = $mw->Photo( 'resized' );
    $img2->copy( $img1, -shrink, -subsample => $factor, $factor );
    $end = time();
    printf("Tk::Photo Shrink Operation time %.4f\n", $end - $start);
    print "Resized width " . $img2->width . "\n";
    print "Resized height " . $img2->height . "\n";
    
    if ($current_image->{Orientation} eq "Rotate 90 CW") {
        print "Creating rotated image\n";
        $start = time();
        my $rotated_img = $mw->Photo( 'rotated',
                                      -width => $img2->height,
                                      -height => $img2->width );
        for (my $y = 0; $y < $img2->height; $y++) {
            my $curpix = $img2->data(-from => 0, $y, $img2->width, $y + 1);
            $curpix =~ s/^{(.*)}$/$1/;
            $rotated_img->put($curpix, -to => $img2->height - $y - 1, 0);
            $img2->idletasks;
        }
        $end = time();
        printf("Tk::Photo Rotate Operation time %.4f\n", $end - $start);
        print "Rotated width " . $rotated_img->width . "\n";
        print "Rotated height " . $rotated_img->height . "\n";
        $start = time();
        $imagit->configure(
            -image => 'rotated',
            -width => $rotated_img->width,
            -height => $rotated_img->height,
        );
        $end = time();
        printf("Tk::Photo Configure Operation time %.4f\n", $end - $start);
    } else {
        $start = time();
        $imagit->configure(
            -image => 'resized',
            -width => $img2->width,
            -height => $img2->height,
        );
        $end = time();
        printf("Tk::Photo Configure Operation time %.4f\n", $end - $start);
    }
    
}

sub keypress {
    my $widget = shift;

    my $e = $widget->XEvent;
    my ($keysym_text, $keysym_decimal) = ($e->K, $e->N);

    print "keysym=$keysym_text, numeric=$keysym_decimal\n";
    if ($keysym_text eq "Right") {
        $ii++;
        if ($ii >= scalar(@files)) {
            $ii = 0;
        }
        show_image();
    } elsif ($keysym_text eq "Left") {
        $ii--;
        if ($ii < 0) {
            $ii = scalar(@files) - 1;
        }
        show_image();
    } elsif ($keysym_text eq "w") {
        wow();
        rate(5);
        $ii++;
        if ($ii >= scalar(@files)) {
            $ii = 0;
        }
        show_image();
    } elsif ( $e->N > 48 && $e->N < 54 ) {
        rate($e->N - 48);
        $ii++;
        if ($ii >= scalar(@files)) {
            $ii = 0;
        }
        show_image();
    }
}

sub wow {
    print "Wow!!! $current_image->{filename}\n";
    $current_image->{exifTool}->SetNewValue("Comment",$WOW_TEXT);
    $current_image->{exifTool}->SetNewValue("XPComment",$WOW_TEXT);
    $current_image->{exifTool}->WriteInfo($current_image->{filename});
}

sub rate {
    my $rating = shift;
    print "Rate $current_image->{filename} $rating\n";
    my $ratingpercent = 0;
    if ($rating == 5) {
        $ratingpercent = 99;
    } elsif ($rating == 4) {
        $ratingpercent = 75;
    } elsif ($rating == 3) {
        $ratingpercent = 50;
    } elsif ($rating == 2) {
        $ratingpercent = 25;
    } elsif ($rating == 1) {
        $ratingpercent = 1;
    }
    $current_image->{exifTool}->SetNewValue("Rating",$rating);
    $current_image->{exifTool}->SetNewValue("RatingPercent",$ratingpercent);
    $current_image->{exifTool}->WriteInfo($current_image->{filename});
}

$mw->after( 100, \&show_image );

MainLoop;