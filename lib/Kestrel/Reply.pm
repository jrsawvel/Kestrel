package Reply;

use strict;

use Kestrel::BlogData;

my $pt_db_source       = Config::get_value_for("database_host");
my $pt_db_catalog      = Config::get_value_for("database_name");
my $pt_db_user_id      = Config::get_value_for("database_username");
my $pt_db_password     = Config::get_value_for("database_password");

my $dbtable_content    = Config::get_value_for("dbtable_content");
my $dbtable_users      = Config::get_value_for("dbtable_users");

sub show_reply_form {
    my $tmp_hash = shift;  
 
    my $replytocontentdigest = $tmp_hash->{one};

    if ( !defined($replytocontentdigest) ) {
        Web::report_error("user", "Invalid Function.", "Cannot determine what blog you are replying to.");
    } 
    User::user_allowed_to_function();

    my $logged_in_userid   = User::get_logged_in_userid();
    my %replytoinfo = get_reply_to_info($replytocontentdigest);

    if ( !allowed_to_reply($replytoinfo{replytoid}, $logged_in_userid) ) {
        Web::report_error("user", "Invalid Access.", "You are not logged in, or you already posted a reply.");
    }

    if ( $tmp_hash->{formtype} eq "enhanced" ) {
        Web::set_template_name("enhblogpostform");
    } else {
        Web::set_template_name("blogpostform");
    }

    Web::set_template_variable("replyblogpost", 1);
    Web::set_template_variable("replytotitle", $replytoinfo{replytotitle});
    Web::set_template_variable("replytoid", $replytoinfo{replytoid});
    Web::set_template_variable("replytocontentdigest", $replytocontentdigest);
    Web::display_page("Reply Blog Post Form");
}

sub show_enh_reply_form {
    my $tmp_hash = shift;

    $tmp_hash->{formtype} = "enhanced";

    show_reply_form($tmp_hash);
}

# know the content digest for the blog post that is being replied to, so get other info for this blog post
sub get_reply_to_info {
    my $digest = shift;

    my %hash;

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Web::report_error("system", "Error connecting to database.", $db->errstr) if $db->err;

    $digest = $db->quote($digest);

    my $reply_to_status = Config::get_value_for("reply_to_status");
    my $sql = "select id, authorid, title from $dbtable_content where contentdigest=$digest and type='b' and status in ($reply_to_status) limit 1";

    $db->execute($sql);
    Web::report_error("system", "(77) Error executing SQL", $db->errstr) if $db->err;

    if ( $db->fetchrow ) {
        $hash{replytoid}    = $db->getcol("id");
        $hash{replytoauthorid} = $db->getcol("authorid");
        $hash{replytotitle} = $db->getcol("title");
    }
    Web::report_error("system", "Error retrieving data from database.", $db->errstr) if $db->err;

    $db->disconnect;
    Web::report_error("system", "Error disconnecting from database.", $db->errstr) if $db->err;

    return %hash;
}

# know the id for the blog post that is being replied to, so get other info for this blog post
sub get_parent_blog_info {
    my $parentid= shift;

    my %hash;

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Web::report_error("system", "Error connecting to database.", $db->errstr) if $db->err;

    my $reply_to_status = Config::get_value_for("reply_to_status");
    my $sql = "select title, markupcontent, authorid from $dbtable_content where id=$parentid and type='b' and status in ($reply_to_status)"; 

    $db->execute($sql);
    Web::report_error("system", "(77) Error executing SQL", $db->errstr) if $db->err;

    if ( $db->fetchrow ) {
        $hash{replytotitle} = $db->getcol("title");
        $hash{replytoauthorid} = $db->getcol("authorid");
        my $tmp_markup = $db->getcol("markupcontent");
        $hash{allowreplies}  = Utils::get_power_command_on_off_setting_for("replies", $tmp_markup, 1);
    }
    Web::report_error("system", "Error retrieving data from database.", $db->errstr) if $db->err;

    $db->disconnect;
    Web::report_error("system", "Error disconnecting from database.", $db->errstr) if $db->err;

    return %hash;
}

sub replies_exist {
    my $articleid = shift;
    my $canedit = shift;

    my $hidewhere = "('n')";

    $hidewhere = "('n','y')" if $canedit;
 
    my $cgi_app = Config::get_value_for("cgi_app");

    my $offset = Utils::get_time_offset();

    my @loop_data = ();

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Web::report_error("system", "Error connecting to database.", $db->errstr) if $db->err;

    my $reply_to_status = Config::get_value_for("reply_to_status");

    my $sql = <<EOSQL; 
    SELECT c.id, c.parentid, c.title, u.username, c.hidereply,  
      DATE_FORMAT(DATE_ADD(c.date, interval $offset hour), '%b %d, %Y') AS date 
      FROM $dbtable_content c, $dbtable_users u
      WHERE c.authorid=u.id 
      AND c.parentid = $articleid
      AND c.status in ($reply_to_status)  
      AND c.type in ('b')
      and c.hidereply in $hidewhere
      ORDER BY id asc 
EOSQL

    $db->execute($sql);
    Web::report_error("system", "(106) Error executing SQL", $db->errstr) if $db->err;

    while ( $db->fetchrow ) {
        my %hash;
        $hash{articleid}     = $db->getcol("id");
        $hash{title}         = $db->getcol("title");
        $hash{urltitle}      = Utils::clean_title($hash{title});
        $hash{authorname}    = $db->getcol("username");
        $hash{date}          = $db->getcol("date");
        $hash{cgi_app}       = $cgi_app;
        my $hidereply        = $db->getcol("hidereply");
        if ( $canedit and $hidereply eq "n" ) {
            $hash{useraction}     = "delete";
            $hash{parentid}       = $db->getcol("parentid");
        }
        elsif ( $canedit and $hidereply eq "y" ) {
            $hash{useraction}    = "undelete";
            $hash{parentid}       = $db->getcol("parentid");
        }
        push(@loop_data, \%hash);
    }
    Web::report_error("system", "Error retrieving data from database.", $db->errstr) if $db->err;

    $db->disconnect;
    Web::report_error("system", "Error disconnecting from database.", $db->errstr) if $db->err;

    return @loop_data;
}

sub allowed_to_reply {
    my $articleid = shift;
    my $logged_in_userid = shift;

    if ( !$articleid or !$logged_in_userid ) {
        return 0;
    }

    if ( !User::valid_user() ) {
        return 0;
    }

    my %hash = get_parent_blog_info($articleid);

    if ( !$hash{allowreplies} ) {
        return 0;
    }

    if ( $logged_in_userid == $hash{replytoauthorid} ) {
        return 0;  # if logged in user viewing own blog post, no need to reply to it
    }    

    # now check to see if logged in user has already created a reply blog post. only one reply allowed per post.    

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Web::report_error("system", "Error connecting to database.", $db->errstr) if $db->err;
  
    my $allowed_to_reply_status = Config::get_value_for("allowed_to_reply_status");

    my $sql = <<EOSQL; 
    SELECT id
      FROM $dbtable_content
      WHERE authorid=$logged_in_userid 
      AND parentid = $articleid
      AND status in ($allowed_to_reply_status)
      AND type in ('b')
EOSQL

    $db->execute($sql);
    Web::report_error("system", "(106) Error executing SQL", $db->errstr) if $db->err;

    if ( $db->fetchrow ) {
        return 0;
    }

    return 1;
}

sub hide_reply {
    my $tmp_hash = shift;  
    hide_unhide_reply("hide", $tmp_hash);
}

sub unhide_reply {
    my $tmp_hash = shift;  
    hide_unhide_reply("unhide", $tmp_hash);
}

sub hide_unhide_reply {
    my $action   = shift;
    my $tmp_hash = shift;  

    my $articleid = $tmp_hash->{one}; 
    my $parentid  = $tmp_hash->{two}; 

    my $q = new CGI;

    if ( !$articleid or !$parentid ) {
        Web::report_error("user", "Invalid action.", "Missing article id or parent article id.");
    }

    if ( !Utils::is_numeric($articleid) or !Utils::is_numeric($parentid) ) {
        Web::report_error("user", "Invalid action.", "Missing article id or parent article id.");
    }

    my $logged_in_userid   = User::get_logged_in_userid();
    my $logged_in_username = User::get_logged_in_username();
    my %blog_post          = BlogData::_get_blog_post($parentid);
    if ( !User::user_allowed_to_function() or ($logged_in_username ne $blog_post{authorname})  ) {
        Web::report_error("user", "Invalid action.", "You do not have permission to perform function.");
    }

    my $hidevalue = "";

    if ( $action eq "hide" ) {
        $hidevalue = "y";
    } elsif ( $action eq "unhide" ) {
        $hidevalue = "n";
    }

    my $sql;

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Web::report_error("system", "Error connecting to database.", $db->errstr) if $db->err;

    $sql = "update $dbtable_content set hidereply='$hidevalue' where id=$articleid and parentid=$parentid and parentauthorid=$logged_in_userid";
    $db->execute($sql);
    Web::report_error("system", "(40-b) Error executing SQL", $db->errstr) if $db->err;

    $db->disconnect;
    Web::report_error("system", "Error disconnecting from database.", $db->errstr) if $db->err;

    print $q->redirect( -url => $ENV{HTTP_REFERER});
}

sub get_replies_given_count {
    User::user_allowed_to_function();

    my $logged_in_userid = User::get_logged_in_userid();

    my $replies_given_count =0;

    return $replies_given_count if !$logged_in_userid; 

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Web::report_error("system", "Error connecting to database.", $db->errstr) if $db->err;

    my $sql;
    $sql = "select count(*) as repliesgivencount from $dbtable_content where authorid=$logged_in_userid and parentid>0 and type='b' and status in ('o','p')";

    $db->execute($sql);
    Web::report_error("system", "(61) Error executing SQL", $db->errstr) if $db->err;

    if ( $db->fetchrow ) {
        $replies_given_count = $db->getcol("repliesgivencount");
    }
    Web::report_error("system", "Error retrieving data from database.", $db->errstr) if $db->err;

    $db->disconnect();
    Web::report_error("system", "Error disconnecting from database.", $db->errstr) if $db->err;

    return $replies_given_count;
}

sub get_replies_received_count {
    User::user_allowed_to_function();

    my $logged_in_userid = User::get_logged_in_userid();

    my $replies_received_count = 0;

    return $replies_received_count if !$logged_in_userid; 

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Web::report_error("system", "Error connecting to database.", $db->errstr) if $db->err;

    my $sql;
    $sql = "select count(*) as repliesreceivedcount from $dbtable_content where parentauthorid=$logged_in_userid and type='b' and status in ('o','p')";

    $db->execute($sql);
    Web::report_error("system", "(61) Error executing SQL", $db->errstr) if $db->err;

    if ( $db->fetchrow ) {
        $replies_received_count = $db->getcol("repliesreceivedcount");
    }
    Web::report_error("system", "Error retrieving data from database.", $db->errstr) if $db->err;

    $db->disconnect();
    Web::report_error("system", "Error disconnecting from database.", $db->errstr) if $db->err;

    return $replies_received_count;
}

sub show_replies_given {
    User::user_allowed_to_function();

    my $userid = User::get_logged_in_userid();

    my $replies_given;

    Web::set_template_name("repliesgiven");

    $replies_given = _get_replies_given($userid);

    if ( exists($replies_given->[0]->{title}) ) {
           Web::set_template_loop_data("repliesgiven", $replies_given);
    }

    Web::display_page("Your Replies Given");
}

sub _get_replies_given {
    my $userid = shift;

    my @loop_data;

    my $cgi_app = Config::get_value_for("cgi_app");

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Web::report_error("system", "Error connecting to database.", $db->errstr) if $db->err;

    my $sql;

    $sql = "select id, parentid, title from $dbtable_content where parentid>0 and authorid=$userid and type='b' and status in ('o','p')";
    $db->execute($sql);
    Web::report_error("system", "(61) Error executing SQL", $db->errstr) if $db->err;

    while ( $db->fetchrow ) {
        my %hash = ();
        $hash{articleid}   = $db->getcol("id");
        $hash{parentid}    = $db->getcol("parentid");
        $hash{title}       = $db->getcol("title");
        $hash{cgi_app}     = $cgi_app;
        push(@loop_data, \%hash);
    }
    Web::report_error("system", "Error retrieving data from database.", $db->errstr) if $db->err;

    $db->disconnect();
    Web::report_error("system", "Error disconnecting from database.", $db->errstr) if $db->err;

    return \@loop_data;
}



1;

