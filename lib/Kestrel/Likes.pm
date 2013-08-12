package Likes;

use strict;

my $pt_db_source       = Config::get_value_for("database_host");
my $pt_db_catalog      = Config::get_value_for("database_name");
my $pt_db_user_id      = Config::get_value_for("database_username");
my $pt_db_password     = Config::get_value_for("database_password");

my $dbtable_likes   = Config::get_value_for("dbtable_likes");
my $dbtable_content = Config::get_value_for("dbtable_content");
my $dbtable_users   = Config::get_value_for("dbtable_users");

sub get_like_count {
    my $articleid = shift;

    my $likecount=0;

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Web::report_error("system", "Error connecting to database.", $db->errstr) if $db->err;

    my $sql;
    $sql = "select count(*) as likecount from $dbtable_likes where articleid=$articleid"; 

    $db->execute($sql);
    Web::report_error("system", "(61) Error executing SQL", $db->errstr) if $db->err;

    if ( $db->fetchrow ) {
        $likecount = $db->getcol("likecount");
    }
    Web::report_error("system", "Error retrieving data from database.", $db->errstr) if $db->err;

    $db->disconnect();
    Web::report_error("system", "Error disconnecting from database.", $db->errstr) if $db->err;

    return $likecount;
}

sub is_post_liked_by_user {
    my $articleid = shift;

    my $is_liked = 0;

    my $logged_in_userid = User::get_logged_in_userid();

    return $is_liked if !$logged_in_userid; 

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Web::report_error("system", "Error connecting to database.", $db->errstr) if $db->err;

    my $sql;
    $sql = "select id from $dbtable_likes where articleid=$articleid and userid=$logged_in_userid";

    $db->execute($sql);
    Web::report_error("system", "(61) Error executing SQL", $db->errstr) if $db->err;
   
    if ( $db->fetchrow ) {
        $is_liked = 1;      
    }
    Web::report_error("system", "Error retrieving data from database.", $db->errstr) if $db->err;

    $db->disconnect();
    Web::report_error("system", "Error disconnecting from database.", $db->errstr) if $db->err;

    return $is_liked;
}

sub like_post {
    my $tmp_hash = shift;  

    my $articleid = $tmp_hash->{one}; 

    User::user_allowed_to_function();

    my $q = new CGI;

    _like_post(User::get_logged_in_userid(), $articleid);

    print $q->redirect( -url => Utils::get_http_referer());
}

sub unlike_post {
    my $tmp_hash = shift;  

    my $articleid = $tmp_hash->{one}; 

    User::user_allowed_to_function();

    my $q = new CGI;

    _unlike_post(User::get_logged_in_userid(), $articleid);

    print $q->redirect( -url => Utils::get_http_referer());
}

sub show_likes_given {
    User::user_allowed_to_function();

    my $userid = User::get_logged_in_userid();

    my $likes_given;

    Web::set_template_name("likesgiven");

    $likes_given = _get_likes_given($userid);

    if ( exists($likes_given->[0]->{title}) ) {
           Web::set_template_loop_data("likesgiven", $likes_given);
    }

    Web::display_page("Your Likes Given");
}

sub show_likes_received {
    User::user_allowed_to_function();

    my $userid = User::get_logged_in_userid();

    my $likes_received;

    Web::set_template_name("likesreceived");

    $likes_received = _get_likes_received($userid);

    if ( exists($likes_received->[0]->{title}) ) {
           Web::set_template_loop_data("likesreceived", $likes_received);
    }

    Web::display_page("Your Posts with Likes Received");
}

sub _like_post {
    my $userid = shift;
    my $articleid = shift;

    my $sql;

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Web::report_error("system", "Error connecting to database.", $db->errstr) if $db->err;

    $sql = "select id from $dbtable_likes where articleid=$articleid and userid=$userid";
    $db->execute($sql);
    Web::report_error("system", "(40-a) Error executing SQL", $db->errstr) if $db->err;

    if ( $db->fetchrow ) {
        $db->disconnect;
        Web::report_error("user", "Invalid action performed.", "You already liked this post.");
    }

    my $datetime = Utils::create_datetime_stamp();

    my $datetime = $db->quote($datetime);

    $sql =  "insert into $dbtable_likes (userid, articleid, createddate) ";
    $sql .= " values ($userid, $articleid, $datetime)";
    $db->execute($sql);
    Web::report_error("system", "(40-c) Error executing SQL", $db->errstr) if $db->err;
     
    $sql = "update $dbtable_content set likes=likes+1 where id=$articleid";
    $db->execute($sql);
    Web::report_error("system", "(40-c) Error executing SQL", $db->errstr) if $db->err;
 
    $db->disconnect;
    Web::report_error("system", "Error disconnecting from database.", $db->errstr) if $db->err;
}

sub _unlike_post {
    my $userid = shift;
    my $articleid = shift;

    my $sql;

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Web::report_error("system", "Error connecting to database.", $db->errstr) if $db->err;

    $sql = "select id from $dbtable_likes where articleid=$articleid and userid=$userid";
    $db->execute($sql);
    Web::report_error("system", "(40-a) Error executing SQL", $db->errstr) if $db->err;

    if ( !$db->fetchrow ) {
        $db->disconnect;
        Web::report_error("user", "Invalid action performed.", "Post was not liked.");
    }

    $sql =  "delete from $dbtable_likes where articleid=$articleid and userid=$userid";
    $db->execute($sql);
    Web::report_error("system", "(40-c) Error executing SQL", $db->errstr) if $db->err;
      
    $sql = "update $dbtable_content set likes=likes-1 where id=$articleid";
    $db->execute($sql);
    Web::report_error("system", "(40-c) Error executing SQL", $db->errstr) if $db->err;
 
    $db->disconnect;
    Web::report_error("system", "Error disconnecting from database.", $db->errstr) if $db->err;
}

sub _get_likes_given {
    my $userid = shift;

    my @loop_data;

    my $cgi_app = Config::get_value_for("cgi_app");

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Web::report_error("system", "Error connecting to database.", $db->errstr) if $db->err;

    my $sql;

    $sql = "select c.id, c.title, c.type, u.username ";
    $sql .= " from $dbtable_content c, $dbtable_likes l, $dbtable_users u ";
    $sql .= " where l.articleid = c.id and c.authorid=u.id and l.userid=$userid and c.status='o' order by l.createddate desc";

    $db->execute($sql);
    Web::report_error("system", "(61) Error executing SQL", $db->errstr) if $db->err;

    while ( $db->fetchrow ) {
        my %hash = ();
        $hash{articleid}   = $db->getcol("id");
        $hash{title}       = $db->getcol("title");
        $hash{author}      = $db->getcol("username");
        $hash{cgi_app}     = $cgi_app;

        my $tmp_type = $db->getcol("type");
        if ( $tmp_type eq "b" ) {
            $hash{posttype} = "blogpost";
        } elsif ( $tmp_type eq "m" ) {
            $hash{posttype} = "microblogpost";
            if ( length($hash{title}) > 75 ) {
                $hash{title} = substr $hash{title}, 0, 75;
                $hash{title} .= "...";
            }
        }

        push(@loop_data, \%hash);
    }
    Web::report_error("system", "Error retrieving data from database.", $db->errstr) if $db->err;

    $db->disconnect();
    Web::report_error("system", "Error disconnecting from database.", $db->errstr) if $db->err;

    return \@loop_data;
}

sub _get_likes_received {
    my $userid = shift;

    my @loop_data;

    my $cgi_app = Config::get_value_for("cgi_app");

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Web::report_error("system", "Error connecting to database.", $db->errstr) if $db->err;

    my $sql;

    $sql = "select id, title, type, likes ";
    $sql .= " from kestrel_content "; 
    $sql .= " where authorid=$userid and likes > 0 and status='o' order by likes desc";

    $db->execute($sql);
    Web::report_error("system", "(61) Error executing SQL", $db->errstr) if $db->err;

    while ( $db->fetchrow ) {
        my %hash = ();
        $hash{articleid}   = $db->getcol("id");
        $hash{title}       = $db->getcol("title");
        $hash{likes}       = $db->getcol("likes");
        $hash{cgi_app}     = $cgi_app;

        my $tmp_type = $db->getcol("type");
        if ( $tmp_type eq "b" ) {
            $hash{posttype} = "blogpost";
        } elsif ( $tmp_type eq "m" ) {
            $hash{posttype} = "microblogpost";
            if ( length($hash{title}) > 75 ) {
                $hash{title} = substr $hash{title}, 0, 75;
                $hash{title} .= "...";
            }
        }

        push(@loop_data, \%hash);
    }
    Web::report_error("system", "Error retrieving data from database.", $db->errstr) if $db->err;

    $db->disconnect();
    Web::report_error("system", "Error disconnecting from database.", $db->errstr) if $db->err;

    return \@loop_data;
}

sub get_likes_given_count {
    User::user_allowed_to_function();

    my $logged_in_userid = User::get_logged_in_userid();

    my $likes_given_count =0;

    return $likes_given_count if !$logged_in_userid; 

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Web::report_error("system", "Error connecting to database.", $db->errstr) if $db->err;

    my $sql;
    $sql = "select count(*) as likesgivencount from $dbtable_likes where userid=$logged_in_userid"; 

    $db->execute($sql);
    Web::report_error("system", "(61) Error executing SQL", $db->errstr) if $db->err;

    if ( $db->fetchrow ) {
        $likes_given_count = $db->getcol("likesgivencount");
    }
    Web::report_error("system", "Error retrieving data from database.", $db->errstr) if $db->err;

    $db->disconnect();
    Web::report_error("system", "Error disconnecting from database.", $db->errstr) if $db->err;

    return $likes_given_count;
}

sub get_likes_received_count {
    User::user_allowed_to_function();

    my $logged_in_userid = User::get_logged_in_userid();

    my $likes_received_count = 0;

    return $likes_received_count if !$logged_in_userid; 

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Web::report_error("system", "Error connecting to database.", $db->errstr) if $db->err;

    my $sql;
    $sql = "select count(*) as likesreceivedcount from $dbtable_content where authorid=$logged_in_userid and likes > 0"; 

    $db->execute($sql);
    Web::report_error("system", "(61) Error executing SQL", $db->errstr) if $db->err;

    if ( $db->fetchrow ) {
        $likes_received_count = $db->getcol("likesreceivedcount");
    }
    Web::report_error("system", "Error retrieving data from database.", $db->errstr) if $db->err;

    $db->disconnect();
    Web::report_error("system", "Error disconnecting from database.", $db->errstr) if $db->err;

    return $likes_received_count;
}

sub kdebug {
    my $str = shift;
    Web::report_error("user", "debug", $str);
}

1;
