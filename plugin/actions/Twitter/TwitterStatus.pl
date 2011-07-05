#!/usr/bin/perl -w
    
    # import modules we're going to be using
    use strict;
    use diagnostics;
    use Net::Twitter;
    use Data::Dumper;
    use XML::Simple;
    use Getopt::Long;
    Getopt::Long::Configure('bundling');
     
     
     
    # Define/initialize some variables
    my $action;
    my $twitt;
    my $status;
    my @result;
    my $results;
    my $travHome = "/usr/local/traverse";
    my $homeDir = "$travHome/plugin/actions/Twitter";
    my $PROGNAME   = "TwitterStatus.pl";
    my $logFile = "/tmp/debug-$PROGNAME.log";
    my $dateTime = `/bin/date +%Y/%m/%d:%H:%M:%S`;
    chomp($dateTime);
    
    my $accessInfo = { consumer_key => "",
                       consumer_secret => "",
                       access_token => "",
                       access_token_secret => "", };
    
    my $keyfileName = "TwitterKeyfile.xml";
    my $keyFile;
    my $keyUser = "";
    my $DEBUG = 0;
    
    
    sub show_help() {
        printf "\n$PROGNAME - update twitter status with info.\n";
        printf "\nUsage : $PROGNAME [--keyfile] [--keyuser=s] [--ckey=s] [--csecret=s] [--atoken=s] [--asecret=s] --status=s [--debug]\n\n";
        printf "--h           This Screen\n";
        printf "--ckey=s      Twitter Consumer Key.\n";
        printf "--csecret=s   Twitter Consumer secret.\n";
        printf "--atoken=s    Twitter Access Token.\n";
        printf "--asecret=s   Twitter Access Token Secret.\n";
        printf "--status=s    Twitter status.\n";
        printf "--keyfile     Twitter Keyfile (contains consumer keys/secrets etc.)\n";
        printf "--keyuser=s   UserID within Keyfile to use\n";
        printf "--debug       Enable debug\n";
        printf "\n";
        printf "There are 2 methods to use this script, the first method, is to add the\n";
        printf "access information to the Twitterkeyfile.xml file, and use the --keyfile\n";
        printf " and keyuser=<username> option.   If this isn't possible, then you need \n";
        printf " to supply all 4 parameters on the command line using the --ckey, --csecret\n";
        printf " --atoken and --asecret parameters.   The status you want to set will be \n";
        printf " supplied by the --status parameter.\n\n";
        exit(-2);
    }


    
    sub process_arguments() {
        my $helpme;
        
        my $pstat = GetOptions(
            "h"           => \$helpme,
            "debug"       => \$DEBUG,
            "ckey=s"      => \$accessInfo->{consumer_key},
            "csecret=s"   => \$accessInfo->{consumer_secret},
            "atoken=s"    => \$accessInfo->{access_token},
            "asecret=s"   => \$accessInfo->{access_token_secret},
            "status=s"    => \$status,
            "keyfile"     => \$keyFile,
            "keyuser=s"   => \$keyUser,
          );
       
        if($pstat == 0 || ($status eq "")) { show_help(); }
        if($helpme) { show_help(); }
       
        return 0;
    }
    
    
    sub exit_now {
      my ($txt, $retval) = @_;
      print $txt;
      exit($retval);
    }
    
    sub logIt {
        my $stuff = $_[0];
        my $line;
        
        open FILE,">>$logFile";
        chomp($stuff);
        print FILE $dateTime." -> ".$stuff."\n";
        
        close FILE;
        return;
   }
   
   sub logItArray {
        my @stuff = @_;
        my $line;
        
        open FILE,">>$logFile";
        foreach $line (@stuff) {
            chomp($line);
            print FILE $dateTime." -> ".$line."\n";
        }
        
        close FILE;
        return;
   }
   
   
   
   sub readAccessInfo {
       my $info = $_[0];
       my $keyFile = $_[1];
       my $keyUser = $_[2];
       
       # check if keyfile exists or not
       if (!(-f "$homeDir/$keyFile")) {
           logIt("Keyfile specified, but does not exist: $homeDir/$keyFile");
           exit(-1);
       }
       
       my $xs = new XML::Simple(keeproot => 1, searchpath => ".",
                         suppressempty => 1);
 
       # read in and parse the XML config file.
       my $ref = $xs->XMLin("$homeDir/$keyFile");
 
       # now pull out the test information, so we can work on provisioning.
       my %keys = %{$ref->{"TwitterKeyfile"}};

       if (exists($keys{$keyUser})) {
          my %userInfo = %{$keys{$keyUser}};
          $accessInfo->{consumer_key} =  $userInfo{consumerKey};
          $accessInfo->{consumer_secret} = $userInfo{consumerSecret};
          $accessInfo->{access_token} = $userInfo{accessToken};
          $accessInfo->{access_token_secret} = $userInfo{accessTokenSecret};
       } else {
          logIt("User $keyUser doesn't exist in keyfile: $homeDir/$keyFile!");
          print "User $keyUser doesn't exist in keyfile: $homeDir/$keyFile!\n";
          exit(-1);
       }
       
       return;
   }
       
    
    
    # Get command line args
    my $cstat = process_arguments();
    
    if ( $cstat != 0 ) {
      show_help();
      exit(1);
    }
    
    # check if the user has identified that they want to use a keyfile
    # if so we're going to read the access credentials from that.
    if ($keyFile) {
        readAccessInfo($accessInfo,$keyfileName,$keyUser);
    }
    
    # we must have at least the consumer key and consumer secret to connect to 
    # the twitter system, so if they don't exist, then report the error and exit.
    if (($accessInfo->{consumer_key} eq "") || ($accessInfo->{consumer_secret} eq "")) {
        logIt("ERROR: Consumer key & consumer secret needed!");
        print "ERROR: Consumer key & consumer secret needed!\n";
        show_help();
        exit(-1);
    }
    
    if ($DEBUG) {
        print Dumper($accessInfo);
        logIt("accessInfo: ".Dumper($accessInfo));
    }
    
    # now we need to open a twitter connection
    $twitt = Net::Twitter->new(
        traits   => ['API::REST', 'OAuth'],
        %{$accessInfo},
    );
    
    if ($@ && ($@->code != 200)) {
        logIt("HTTP Response Code: ", $@->code);
        logIt("HTTP Message......: ", $@->message);
        logIt("Twitter error.....: ", $@->error);
        logIt("Error: ".$@->isa('Net::Twitter::Error'));
        
        # The client is not yet authorized: Do it now
        print "Authorize this app at ", $twitt->get_authorization_url, " and enter the PIN#\n";
  
        my $pin = <STDIN>; # wait for input
        chomp $pin;
  
        my($access_token, $access_token_secret, $user_id, $screen_name) = $twitt->request_access_token(verifier => $pin);
        logIt("received access token:        $access_token");
        logIt("received access token_secret: $access_token_secret");
        logIt("user id:                      $user_id");
        logIt("received screen name:         $screen_name");
    }
  
    
    eval { $twitt->test; };
  
    if ($@ && ($@->code != 200)) {
        logIt("HTTP Response Code: ", $@->code);
        logIt("HTTP Message......: ", $@->message);
        logIt("Twitter error.....: ", $@->error);
        logIt("Error: ".$@->isa('Net::Twitter::Error'));
        
        # The client is not yet authorized: Do it now
        print "Authorize this app at ", $twitt->get_authorization_url, " and enter the PIN#\n";
  
        my $pin = <STDIN>; # wait for input
        chomp $pin;
  
        my($access_token, $access_token_secret, $user_id, $screen_name) = $twitt->request_access_token(verifier => $pin);
        logIt("received access token:        $access_token");
        logIt("received access token_secret: $access_token_secret");
        logIt("user id:                      $user_id");
        logIt("received screen name:         $screen_name");
    }
    
    
    
    eval {
        $twitt->update( { status => $status });
    };
    
    if ( $@ ) {
        # encountered an error
        if ( $@->isa('Net::Twitter::Error') ) {
            #... use the thrown error obj
            printf $@->error."\n" if ($DEBUG);
            logIt($@->error);
            exit(-1);
        }
        else {
            # something bad happened!
            printf $@."\n" if ($DEBUG);
            logIt($@);
            exit(-1);
        }
    }
    exit(0);