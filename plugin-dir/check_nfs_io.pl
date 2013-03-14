#!/usr/bin/perl -w
# nagios: -epn

#######################################################
#                                                     #
#  Name:    check_nfs_io                              #
#                                                     #
#  Version: 0.2                                       #
#  Created: 2013-03-11                                #
#  License: GPL - http://www.gnu.org/licenses         #
#  Copyright: (c)2013 ovido gmbh, http://www.ovido.at #
#  Author:  Rene Koch <r.koch@ovido.at>               #
#  Credits: s IT Solutions AT Spardat GmbH            #
#  URL: https://labs.ovido.at/monitoring              #
#                                                     #
#######################################################

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Changelog:
# * 0.2.0 - Thu Mar 14 2013 - Rene Koch <r.koch@ovido.at>
# - Changed performance data output
# * 0.1.0 - Mon Mar 11 2013 - Rene Koch <r.koch@ovido.at>
# - This is the first public beta release of new plugin check_nfs_io

use strict;
use Getopt::Long;
use List::Util qw( min max sum );

# Configuration
my $o_runs	= 5;		# nfsiostat runs
my $o_interval	= 1;		# nfsiostat interval

# create performance data
# 0 ... disabled
# 1 ... enabled
my $perfdata	= 1;

# Variables
my $prog	= "check_nfs_io";
my $version	= "0.2";
my $projecturl  = "https://labs.ovido.at/monitoring/wiki/check_nfs_io";

my $o_verbose	= undef;	# verbosity
my $o_help	= undef;	# help
my $o_version	= undef;	# version
my @o_exclude	= ();		# exclude shares
my $o_max	= undef;	# get max values
my $o_average	= undef;	# get average values
my $o_warn	= undef;	# warning
my $o_crit	= undef;	# critical
my @warn	= ();
my @crit	= ();

my %status	= ( ok => "OK", warning => "WARNING", critical => "CRITICAL", unknown => "UNKNOWN");
my %ERRORS	= ( "OK" => 0, "WARNING" => 1, "CRITICAL" => 2, "UNKNOWN" => 3);

my $statuscode	= "unknown";
my $statustext	= "";
my $perfstats	= "|";
my %errors;

#***************************************************#
#  Function: parse_options                          #
#---------------------------------------------------#
#  parse command line parameters                    #
#                                                   #
#***************************************************#
sub parse_options(){
  Getopt::Long::Configure ("bundling");
  GetOptions(
	'v+'	=> \$o_verbose,		'verbose+'	=> \$o_verbose,
	'h'	=> \$o_help,		'help'		=> \$o_help,
	'V'	=> \$o_version,		'version'	=> \$o_version,
	'r:i'	=> \$o_runs,		'runs:i'	=> \$o_runs,
	'i:i'	=> \$o_interval,	'interval:i'	=> \$o_interval,
	'e:s'	=> \@o_exclude,		'exclude:s'	=> \@o_exclude,
	'm'	=> \$o_max,		'max'		=> \$o_max,
	'a'	=> \$o_average,		'average'	=> \$o_average,
	'w:s'	=> \$o_warn,		'warning:s'	=> \$o_warn,
	'c:s'	=> \$o_crit,		'critical:s'	=> \$o_crit
  );

  # process options
  print_help()		if defined $o_help;
  print_version()	if defined $o_version;

  # can't use max and average
  if (defined $o_max && defined $o_average){
    print "Can't use max and average at the same time!\n";
    print_usage();
    exit $ERRORS{$status{'unknown'}};
  }

  if ((! defined $o_warn) || (! defined $o_crit)){
    print "Warning and critical values are required!\n";
    print_usage();
    exit $ERRORS{$status{'unknown'}};
  }

  # check warning and critical
  if ($o_warn !~ /^(\d+)(\.?\d+)*,{1}(\d+)(\.?\d+)*$/){
    print "Please give proper warning values!\n";
    print_usage();
    exit $ERRORS{$status{'unknown'}};
  }else{
    @warn = split /,/, $o_warn;
  }

  if ($o_crit !~ /^(\d+)(\.?\d+)*,{1}(\d+)(\.?\d+)*$/){
    print "Please give proper critical values!\n";
    print_usage();
    exit $ERRORS{$status{'unknown'}};
  }else{
    @crit = split /,/, $o_crit;
  }

  # verbose handling
  $o_verbose = 0 if ! defined $o_verbose;

}


#***************************************************#
#  Function: print_usage                            #
#---------------------------------------------------#
#  print usage information                          #
#                                                   #
#***************************************************#
sub print_usage(){
  print "Usage: $0 [-v] [-r <runs>] [-i <interval>] [-e <exclude>] [-m|-a] \n";
  print "        -w <avg_rtt_read>,<avg_rtt_write> -c <avg_rtt_read>,<avg_rtt_write>\n";
}


#***************************************************#
#  Function: print_help                             #
#---------------------------------------------------#
#  print help text                                  #
#                                                   #
#***************************************************#
sub print_help(){
  print "\nLinux NFS share I/O checks for Icinga/Nagios version $version\n";
  print "GPL license, (c)2013 - Rene Koch <r.koch\@ovido.at>\n\n";
  print_usage();
  print <<EOT;

Options:
 -h, --help
    Print detailed help screen
 -V, --version
    Print version information
 -r, --runs=INTEGER
    nfsiostat count (default: $o_runs)
 -i, --interval=INTEGER
    nfsiostat interval (default: $o_interval)
 -e, --exclude=REGEX
    Regex to exclude NFS mount points from beeing checked
    Note: use client mount point instead of share
          e.g. -e "/mnt/nfs"
 -m, --max
    Use max. values of runs (default)
 -a, --average
    Use average values of runs 
 -w, --warning=<avg_rtt_read>,<avg_rtt_write>
    Value to result in warning status (ms)
 -c, --critical=<avg_rtt_read>,<avg_rtt_write>
    Value to result in critical status (ms)
 -v, --verbose
    Show details for command-line debugging
    (Icinga/Nagios may truncate output)

Send email to r.koch\@ovido.at if you have questions regarding use
of this software. To submit patches of suggest improvements, send
email to r.koch\@ovido.at
EOT

exit $ERRORS{$status{'unknown'}};
}



#***************************************************#
#  Function: print_version                          #
#---------------------------------------------------#
#  Display version of plugin and exit.              #
#                                                   #
#***************************************************#

sub print_version{
  print "$prog $version\n";
  exit $ERRORS{$status{'unknown'}};
}


#***************************************************#
#  Function: main                                   #
#---------------------------------------------------#
#  The main program starts here.                    #
#                                                   #
#***************************************************#

# parse command line options
parse_options();

my $cmd = undef;
my $shares = "";

# get list of NFS shares
my @tmp = `sudo /usr/sbin/nfsiostat`;
for (my $i=0;$i<=$#tmp;$i++){
  next unless $tmp[$i] =~ /mounted on/;
  chomp $tmp[$i];
  # remove : from mount point
  chop $tmp[$i];
  my @share = split / /, $tmp[$i];

  # match shares with exclude list
  if (scalar (@o_exclude) > 0){
    my $match = 0;
    for (my $x=0;$x<=$#o_exclude;$x++){
      $match = 1 if $share[3] =~ m!$o_exclude[$x]!;
    }
    $shares .= " " . $share[3] unless $match == 1;
  }else{
    $shares .= " " . $share[3];
  }
}

if ($shares eq ""){
  exit_plugin("unknown","No NFS shares left to check!");
}

$cmd = "sudo /usr/sbin/nfsiostat " . $o_interval . " " . $o_runs . $shares;

# get statistics from nfsiostat
my %nfsiostat;
my $share = undef;
my $x = -1;
my $first_share = undef;

my @result = `$cmd`;
for (my $i=0;$i<=$#result;$i++){

  $result[$i] =~ s/\s+/ /g;

  # example output to parse
  #nfs-server:/data/nfs mounted on /mnt/nfs:
  #
  #   op/s		rpc bklog
  #   0.02 	   0.00
  #read:             ops/s		   kB/s		  kB/op		retrans		avg RTT (ms)	avg exe (ms)
  #		  0.000 	  0.000 	  0.000        0 (0.0%) 	  0.000 	  0.000
  #write:            ops/s		   kB/s		  kB/op		retrans		avg RTT (ms)	avg exe (ms)
  #		  0.000 	  0.000 	  0.000        0 (0.0%) 	  0.000 	  0.000
  
  # get NFS statistics
  my @tmp = split / /, $result[$i];

  if ( $result[$i] =~ /mounted on/ ){
    # NFS share name
    $share = $tmp[0];
    # set counter
    $first_share = $share if ! defined $first_share;
    $x++ if "$first_share" eq "$share";
  }elsif ( $result[$i] =~ /^(\s){1}((\d)+\.(\d){3}(\s){1}){3}/ ){
    if ( $result[$i-1] =~ /^read:/ ){
      # Read stats
      $nfsiostat{$share}{'rs'}[$x] = $tmp[1];
      $nfsiostat{$share}{'rkBs'}[$x] = $tmp[1];
      $nfsiostat{$share}{'rrtt'}[$x] = $tmp[1];
      $nfsiostat{$share}{'rexe'}[$x] = $tmp[1];
    }elsif ( $result[$i-1] =~ /^write:/ ){
      # Write stats
      $nfsiostat{$share}{'ws'}[$x] = $tmp[1];
      $nfsiostat{$share}{'wkBs'}[$x] = $tmp[1];
      $nfsiostat{$share}{'wrtt'}[$x] = $tmp[1];
      $nfsiostat{$share}{'wexe'}[$x] = $tmp[1];
    }
  }

}


# do some calculations
foreach my $nfsshare (keys %nfsiostat){
  my $nfsio = undef;
  my $value = undef;
  my ($rs, $ws) = undef;
  my $tmp_sc = undef;
  my %output;
  foreach my $param (sort keys %{ $nfsiostat{$nfsshare} }){
    # remove first entry when using multiple runs
    shift @{ $nfsiostat{$nfsshare}{$param} } if $o_runs > 1;
    if (defined $o_max || ! defined $o_average){
      $value = max @{ $nfsiostat{$nfsshare}{$param} };
    }else{
      $value = (sum @{ $nfsiostat{$nfsshare}{$param} }) / (scalar @{ $nfsiostat{$nfsshare}{$param} });
    }
    if ($param eq "rs"){
      $rs = $value;
      $perfstats .= "'" . $nfsshare . "_rs'=$value;;;0; ";
    }elsif ($param eq "ws"){
      $ws = $value;
      $perfstats .= "'" . $nfsshare . "_ws'=$value;;;0; ";
    }elsif ($param eq "rkBs"){
      $perfstats .= "'" . $nfsshare . "_rkBs'=$value" . "KB;;;0; ";
    }elsif ($param eq "wkBs"){
      $perfstats .= "'" . $nfsshare . "_wkBs'=$value" . "KB;;;0; ";
    }elsif ($param eq "rrtt"){
      ($statuscode,$tmp_sc) = get_status($value,$warn[0],$crit[0]);
      $output{$nfsshare}{'read avg RTT'} = $value if ( ($tmp_sc eq 'critical') || ($tmp_sc eq 'warning') );
      $nfsio .= "$nfsshare (read avg RTT $value" if $o_verbose >= 1;
      $perfstats .= "'" . $nfsshare . "_r_avg_rtt'=$value " . "ms;$warn[0];$crit[0];0; ";
    }elsif ($param eq "wrtt"){
      ($statuscode,$tmp_sc) = get_status($value,$warn[1],$crit[1]);
      $output{$nfsshare}{'write avg RTT'} = $value if ( ($tmp_sc eq 'critical') || ($tmp_sc eq 'warning') );
      $nfsio .= ", write avg RTT $value" if $o_verbose >= 1;
      $perfstats .= "'" . $nfsshare . "_w_avg_rtt'=$value " . "ms;$warn[1];$crit[1];0; ";
    }elsif ($param eq "rexe"){
      $perfstats .= "'" . $nfsshare . "_r_avg_exe'=$value" . "ms;;;0; ";
    }elsif ($param eq "wexe"){
      $perfstats .= "'" . $nfsshare . "_w_avg_exe'=$value" . "ms;;;0; ";
    }
  }
  my $ops = $rs + $ws;
  $nfsio .= ", ops/s $ops) " if $o_verbose >= 1;

  if (defined $nfsio){
    $statustext .= $nfsio;
  }else{
    # print warning and critical values per nfsshare
    foreach my $nfs (keys %output){
      $statustext .= " $nfsshare (";
      foreach my $parm (keys %{ $output{$nfs} }){
        $statustext .= "$parm $output{$nfs}{$parm}, ";
      }
      chop $statustext;
      chop $statustext;
      $statustext .= ")";
    }
  }
}

$statustext = " on all shares." if $statuscode eq 'ok' && $o_verbose == 0;
# add checked NFS shares to statustext
$statustext .= " [Mount points:$shares]";

$statustext .= $perfstats if $perfdata == 1;
exit_plugin($statuscode,$statustext);


#***************************************************#
#  Function get_status                              #
#---------------------------------------------------#
#  Matches value againts warning and critical       #
#  ARG1: value                                      #
#  ARG2: warning                                    #
#  ARG3: critical                                   #
#***************************************************#

sub get_status{
  my $tmp_sc = undef;
  if ($_[0] >= $_[2]){
    $statuscode = 'critical';
    $tmp_sc = 'critical';
  }elsif ($_[0] >= $_[1]){
    $statuscode = 'warning' if $statuscode ne 'critical';
    $tmp_sc = 'warning';
  }else{
    $statuscode = 'ok' if $statuscode ne 'critical' && $statuscode ne 'warning';
    $tmp_sc = 'ok';
  }
  return ($statuscode,$tmp_sc);
}

#***************************************************#
#  Function exit_plugin                             #
#---------------------------------------------------#
#  Prints plugin output and exits with exit code.   #
#  ARG1: status code (ok|warning|cirtical|unknown)  #
#  ARG2: additional information                     #
#***************************************************#

sub exit_plugin{
  print "NFS I/O $status{$_[0]}: $_[1]\n";
  exit $ERRORS{$status{$_[0]}};
}


exit $ERRORS{$status{'unknown'}};

