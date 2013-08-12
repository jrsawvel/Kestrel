package BlogData;

use strict;

use HTML::Entities;
use Algorithm::Diff;
use Kestrel::Reply;

my $pt_db_source       = Config::get_value_for("database_host");
my $pt_db_catalog      = Config::get_value_for("database_name");
my $pt_db_user_id      = Config::get_value_for("database_username");
my $pt_db_password     = Config::get_value_for("database_password");

my $dbtable_content    = Config::get_value_for("dbtable_content");
my $dbtable_users      = Config::get_value_for("dbtable_users");
my $dbtable_tags       = Config::get_value_for("dbtable_tags");


sub _preview_article {
    my $title            = shift;
    my $markupcontent    = shift;
    my $posttitle        = shift;
    my $formattedcontent = shift;
    my $err_msg          = shift;
    my $replyblogpost    = shift;
    my $replytocontentdigest   = shift;
    my $formtype = shift;

    User::user_allowed_to_function();

    if ( $formtype eq "enhanced" ) {
        Web::set_template_name("enhblogpostform");
    } else { 
        Web::set_template_name("blogpostform");
    }

    Web::set_template_variable("previewingarticle", "1"); 
    Web::set_template_variable("previewtitle", $posttitle);
    Web::set_template_variable("previewarticle", $formattedcontent);
    Web::set_template_variable("article", $markupcontent);

    if ( $err_msg ) {
        Web::set_template_variable("errorexists", "1");
        Web::set_template_variable("errormessage", $err_msg);
    }

    if ( $replyblogpost ) {
        my %replytoinfo = Reply::get_reply_to_info($replytocontentdigest);
        Web::set_template_variable("replyblogpost", 1);
        Web::set_template_variable("replytocontentdigest", $replytocontentdigest);
        Web::set_template_variable("replytotitle", $replytoinfo{replytotitle});
        Web::set_template_variable("replytoid", $replytoinfo{replytoid});
    }

    Web::display_page("Previewing New Blog Post");
    exit;
}

sub _add_blog {
    my $title             = shift;
    my $userid            = shift;
    my $markupcontent     = shift;
    my $formattedcontent  = shift;
    my $replyblogpost     = shift;
    my $replytocontentdigest = shift;
    my $tag_list_str  = shift;

    my $parentid = 0;
    my $parentauthorid = 0;

    my %replytoinfo;
    if ( $replyblogpost ) {
        %replytoinfo = Reply::get_reply_to_info($replytocontentdigest);
        $parentid       = $replytoinfo{replytoid};
        $parentauthorid = $replytoinfo{replytoauthorid};
    }

    my $new_status = 'o'; # default 
    if ( Utils::get_power_command_on_off_setting_for("draft", $markupcontent, 0) ) {
        $new_status = 'p'; # don't display in streams but do display in searches 
    }

    if ( Utils::get_power_command_on_off_setting_for("private", $markupcontent, 0) ) {
        $new_status = 's'; # secret or private post
    }

    if ( Utils::get_power_command_on_off_setting_for("invisible", $markupcontent, 0) ) {
        $formattedcontent = " "; 
    }

    my $code_post = 0;
    if ( Utils::get_power_command_on_off_setting_for("code", $markupcontent, 0) ) {
        $code_post = 1;
        my $tmp_markupcontent = $markupcontent;
        $tmp_markupcontent =~ s/$title//;
        $tmp_markupcontent = Utils::remove_power_commands($tmp_markupcontent);
        $tmp_markupcontent = Utils::trim_spaces($tmp_markupcontent);
        $formattedcontent = HTML::Entities::encode($tmp_markupcontent, '<>');
        # $formattedcontent = "<pre>\n<code>\n" . $formattedcontent . "\n</code>\n</pre>\n";
        $formattedcontent = "<textarea class=\"codetext\" id=\"enhtextareaboxarticle\" rows=\"15\" cols=\"60\" wrap=\"off\" readonly>" . $formattedcontent  . "</textarea>\n";
    }

    my $datetime = Utils::create_datetime_stamp();

    my $type = 'b';

    $tag_list_str = "" if $code_post;

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Web::report_error("system", "Error connecting to database.", $db->errstr) if $db->err;

    $title            = $db->quote($title);
    $markupcontent    = $db->quote($markupcontent);
    $formattedcontent = $db->quote($formattedcontent);
    my $quoted_tag_list_str     = $db->quote("|" . $tag_list_str . "|");

    # create article digest
    my $md5 = Digest::MD5->new;
    $md5->add(Utils::otp_encrypt_decrypt($title, $datetime, "enc"), $userid, $datetime);
    my $contentdigest = $md5->b64digest;
    $contentdigest =~ s|[^\w]+||g;

    my $sql;

    $sql .= "insert into $dbtable_content (parentid, parentauthorid, title, markupcontent, formattedcontent, type, status, authorid, date, contentdigest, createdby, createddate, tags, ipaddress)";
    $sql .= " values ($parentid, $parentauthorid, $title, $markupcontent, $formattedcontent, '$type', '$new_status', $userid, '$datetime', '$contentdigest', $userid, '$datetime', $quoted_tag_list_str, '$ENV{REMOTE_ADDR}')";

    my $articleid = $db->execute($sql);
    Web::report_error("system", "(30) Error executing SQL", $db->errstr) if $db->err;
 
    # remove beginning and ending pipe delimeter to make a proper delimited string
    $tag_list_str =~ s/^\|//;
    $tag_list_str =~ s/\|$//;
    my @tags = split(/\|/, $tag_list_str);
    foreach (@tags) {
        my $tag = $_;
        $tag = $db->quote($tag);
        if ( $tag ) {
            $sql = "insert into $dbtable_tags (name, articleid, type, status, createdby, createddate) "; 
            $sql .= " values ($tag, $articleid, 'b', 'o', $userid, '$datetime') "; 
            $db->execute($sql);
            Web::report_error("system", "(32-a) Error executing SQL", $db->errstr) if $db->err;
        }
    }

    $db->disconnect;
    Web::report_error("system", "Error disconnecting from database.", $db->errstr) if $db->err;

    return $articleid;
}

sub _get_blog_post {
    my $articleid = shift;

    my $cgi_app = Config::get_value_for("cgi_app");

    my %hash = ();

    my $offset = Utils::get_time_offset();

    my $status_str = "c.status in (" . Config::get_value_for("get_blog_post_status") . ")";

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Web::report_error("system", "Error connecting to database.", $db->errstr) if $db->err;

    my $sql = "select c.id, c.parentid, c.title, c.authorid, c.markupcontent, c.formattedcontent, c.hidereply, c.status, c.version, c.editreason, c.tags, c.contentdigest, c.likes, ";
    $sql .=      "date_format(date_add(c.date, interval $offset hour), '%b %d, %Y') as modifieddate, ";
    $sql .=      "date_format(date_add(c.date, interval $offset hour), '%r') as modifiedtime, ";
    $sql .=      "date_format(date_add(c.createddate, interval $offset hour), '%b %d, %Y') as createddate, ";
    $sql .=      "date_format(date_add(c.createddate, interval $offset hour), '%r') as createdtime, ";
    $sql .=      "date_format(date_add(c.date, interval $offset hour), '%d%b%Y') as urldate, "; 
    $sql .=      "u.username from $dbtable_content c, $dbtable_users u  ";
    $sql .=      "where c.id=$articleid and c.type='b' and $status_str and c.authorid=u.id";

    $db->execute($sql);
    Web::report_error("system", "(31) Error executing SQL", $db->errstr) if $db->err;

    if ( $db->fetchrow ) {
        $hash{articleid}        = $db->getcol("id");
        $hash{parentid}         = $db->getcol("parentid");
        $hash{title}            = $db->getcol("title");

        my $tmp_markup         = $db->getcol("markupcontent");
        if ( $tmp_markup =~ m/^@([0-9]+)\s$/m ) {
            $db->disconnect();
            my %tmp_hash = _get_blog_post($1);
            $tmp_hash{redirectedpage}     = 1;
            $tmp_hash{redirectedpageid}   = $1;
            $tmp_hash{originalid}         = $articleid;
            $tmp_hash{originaltitle}      = $hash{title};
            return %tmp_hash;
        } else {
            $hash{redirectedpage} = 0;
        }

        $hash{cleantitle}       = Utils::clean_title($hash{title}); 
        $hash{blogpost}         = $db->getcol("formattedcontent");
        $hash{urldate}          = $db->getcol("urldate");
        $hash{status}           = $db->getcol("status");
        $hash{hidereply}        = $db->getcol("hidereply");
        $hash{modifieddate}     = $db->getcol("modifieddate");
        $hash{modifiedtime}     = lc($db->getcol("modifiedtime"));
        $hash{createddate}      = $db->getcol("createddate");
        $hash{createdtime}      = lc($db->getcol("createdtime"));
        $hash{authorid}         = $db->getcol("authorid");
        $hash{authorname}       = $db->getcol("username");
        $hash{editreason}       = $db->getcol("editreason");
        $hash{tags}             = $db->getcol("tags");
        $hash{contentdigest}    = $db->getcol("contentdigest");
        $hash{likes}            = $db->getcol("likes");
        $hash{cgi_app}          = $cgi_app;

        $hash{version}             = $db->getcol("version");
        if ( $hash{version} > 1 ) {
            $hash{updated} = 1;
        } else {
            $hash{updated} = 0;
        }

        $hash{toc} = Utils::get_power_command_on_off_setting_for("toc", $tmp_markup, 1);

        if ( $hash{status} eq 's' and !user_owns_blog_post($hash{articleid}, $hash{authorid}) ) {
            %hash = ();
        }    

        if ( $tmp_markup =~ m|^imageheader[\s]*=[\s]*(.+)|im ) {
            $hash{usingimageheader} = 1;
            $hash{imageheaderurl}   = $1;
        }

        if ( $tmp_markup =~ m|^largeimageheader[\s]*=[\s]*(.+)|im ) {
            $hash{usinglargeimageheader} = 1;
            $hash{largeimageheaderurl}   = $1;
        }

        my $tmp_post = Utils::remove_html($hash{blogpost});
        $hash{chars} = length($tmp_post);
        $hash{words} = scalar(split(/\s+/s, $tmp_post));
        $hash{readingtime} = 0;
        $hash{readingtime} = int($hash{words} / 180) if $hash{words} >= 180;

        if ( $hash{status} eq 'v' and !user_owns_blog_post($hash{articleid}, $hash{authorid}) ) {
            if ( Utils::get_power_command_on_off_setting_for("private", $tmp_markup, 0) ) {
                %hash = ();
            } elsif ( _is_top_level_post_private($hash{parentid}) ) {
                %hash = ();
            }
        }
        
    }
    Web::report_error("system", "Error retrieving data from database.", $db->errstr) if $db->err;

    $db->disconnect();
    Web::report_error("system", "Error disconnecting from database.", $db->errstr) if $db->err;

    return %hash;
}

sub _delete_blog_post {
    my $userid = shift;
    my $articleid = shift;

    my $sql;
    my $tag_list_str;

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Web::report_error("system", "Error connecting to database.", $db->errstr) if $db->err;

    my $delete_blog_post_status = Config::get_value_for("delete_blog_post_status");

    $sql = "select id,tags from $dbtable_content where id=$articleid and authorid=$userid and type='b' and status in ($delete_blog_post_status)";
    $db->execute($sql);
    Web::report_error("system", "(40-a) Error executing SQL", $db->errstr) if $db->err;

    if ( !$db->fetchrow ) {
        $db->disconnect;
        Web::report_error("user", "Invalid action performed.", "Content does not exist");
    } else {
        $tag_list_str = $db->getcol("tags");
    }

    $sql = "update $dbtable_content set status='d' where id=$articleid and authorid=$userid and type='b'";
    $db->execute($sql);
    Web::report_error("system", "(40-b) Error executing SQL", $db->errstr) if $db->err;

    if ( $tag_list_str ) {
        # remove beginning and ending pipe delimeter to make a proper delimited string
        $tag_list_str =~ s/^\|//;
        $tag_list_str =~ s/\|$//;
        my @tags = split(/\|/, $tag_list_str);
        foreach (@tags) {
            my $tag = $_;
            $tag = $db->quote($tag);
            if ( $tag ) {
                $sql = "update $dbtable_tags set status='d' where articleid=$articleid and name=$tag";
                $db->execute($sql);
                Web::report_error("system", "(32-a) Error executing SQL", $db->errstr) if $db->err;
            }
        }
    }
      
    $db->disconnect;
    Web::report_error("system", "Error disconnecting from database.", $db->errstr) if $db->err;
}

sub _undelete_blog_post {
    my $userid = shift;
    my $articleid = shift;

    my $sql;
    my $tag_list_str;
    my $status_str = "o";

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Web::report_error("system", "Error connecting to database.", $db->errstr) if $db->err;

    $sql = "select id, tags, markupcontent from $dbtable_content where id=$articleid and authorid=$userid and type='b' and status='d'";
    $db->execute($sql);
    Web::report_error("system", "(41-a) Error executing SQL", $db->errstr) if $db->err;

    if ( !$db->fetchrow ) {
        $db->disconnect;
        Web::report_error("user", "Invalid action performed.", "Content does not exist");
    } else {
        $tag_list_str = $db->getcol("tags");
        my $tmp_markup = $db->getcol("markupcontent");
        if ( Utils::get_power_command_on_off_setting_for("private", $tmp_markup, 0) ) {
            $status_str = "s";
        } elsif ( Utils::get_power_command_on_off_setting_for("draft", $tmp_markup, 0) ) {
            $status_str = "p";
        }
    }

    $sql = "update $dbtable_content set status='$status_str' where id=$articleid and authorid=$userid and type='b'";
    $db->execute($sql);
    Web::report_error("system", "(41-b) Error executing SQL", $db->errstr) if $db->err;

    if ( $tag_list_str ) {
        # remove beginning and ending pipe delimeter to make a proper delimited string
        $tag_list_str =~ s/^\|//;
        $tag_list_str =~ s/\|$//;
        my @tags = split(/\|/, $tag_list_str);
        foreach (@tags) {
            my $tag = $_;
            $tag = $db->quote($tag);
            if ( $tag ) {
                $sql = "update $dbtable_tags set status='o' where articleid=$articleid and name=$tag";
                $db->execute($sql);
                Web::report_error("system", "(32-a) Error executing SQL", $db->errstr) if $db->err;
            }
        }
    }
      
    $db->disconnect;
    Web::report_error("system", "Error disconnecting from database.", $db->errstr) if $db->err;
}

sub _get_blog_source {
    my $article_id = shift;

    my %article_data = ();

    my $authorid = 0;
    my $parentid = 0;
    my $status;

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Web::report_error("system", "Error connecting to database.", $db->errstr) if $db->err;

    my $get_blog_source_status = Config::get_value_for("get_blog_source_status");

    my $sql = "select parentid, title, authorid, markupcontent, status from $dbtable_content where id = $article_id and status in ($get_blog_source_status)";

    $db->execute($sql);
    Web::report_error("system", "(77) Error executing SQL", $db->errstr) if $db->err;

    if ( $db->fetchrow ) {
        $parentid                    = $db->getcol("parentid");
        $article_data{title}         = $db->getcol("title");
        $authorid                    = $db->getcol("authorid");
        $article_data{markupcontent} = $db->getcol("markupcontent");
        $status                      = $db->getcol("status");
    }
    Web::report_error("system", "Error retrieving data from database.", $db->errstr) if $db->err;

    $db->disconnect;
    Web::report_error("system", "Error disconnecting from database.", $db->errstr) if $db->err;

    if ( $status eq "v" and !user_owns_blog_post($parentid, $authorid) ) {
        if ( Utils::get_power_command_on_off_setting_for("private", $article_data{markupcontent}, 0) ) {
            %article_data = ();
        } elsif ( _is_top_level_post_private($parentid) ) {
            %article_data = ();
        }
    }

    return %article_data;
}

sub _get_blog_post_for_edit {
    my $userid  = shift;      # the logged in user wanting to edit the article
    my $articleid = shift;
    my $sessionid= shift;   # the logged in user wanting to edit the article
    
    my %hash;

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Web::report_error("system", "Error connecting to database.", $db->errstr) if $db->err;

    my $get_blog_post_edit_status = Config::get_value_for("get_blog_post_edit_status");

    my $sql = "select c.id, c.parentid, c.title, c.markupcontent, c.formattedcontent, c.status, c.authorid, c.version, c.contentdigest from $dbtable_content c where c.id=$articleid and c.type in ('b') and c.status in ($get_blog_post_edit_status)";

    $db->execute($sql);
    Web::report_error("system", "(42) Error executing SQL", $db->errstr . " " . $db->err) if $db->err;

    my $ownerid = 0;

    if ( $db->fetchrow ) {
        $hash{articleid}      = $db->getcol("id");
        $hash{parentid}       = $db->getcol("parentid");
        $hash{title}          = $db->getcol("title");
        $hash{markup}         = $db->getcol("markupcontent");
        $hash{formatted}      = $db->getcol("formattedcontent");
        $hash{status}         = $db->getcol("status");
        $hash{versionnumber}  = $db->getcol("version");
        $hash{contentdigest}  = $db->getcol("contentdigest");
        $ownerid              = $db->getcol("authorid");
    }
    else {
        Web::report_error("user", "Error retrieving article.", "Article doesn't exist");
    }
    Web::report_error("system", "Error retrieving data from database.", $db->errstr) if $db->err;

    $db->disconnect();
    Web::report_error("system", "Error disconnecting from database.", $db->errstr) if $db->err;

   if ( !user_owns_blog_post($articleid, $ownerid) ) {
        Web::report_error("user", "Invalid access.", "Unable to edit article.");
   }

    # if ( $ownerid != $userid ) {
    #    # logged in user did not create article and cannot edit 
    #    Web::report_error("user", "Invalid access.", "Unable to edit article.");
    # }

    return %hash;
}

sub _preview_edit {
    my $title             = shift;
    my $markupcontent     = shift;
    my $posttitle         = shift;
    my $formattedcontent  = shift;
    my $articleid         = shift;
    my $contentdigest     = shift;
    my $editreason        = shift;
    my $err_msg           = shift;
    my $formtype          = shift;

    User::user_allowed_to_function();

    if ( $formtype eq "enhanced" ) {
        Web::set_template_name("enheditblogpostform");
    } else { 
        Web::set_template_name("editblogpostform");
    }

    Web::set_template_variable("articleid", $articleid);
    Web::set_template_variable("title", $posttitle);
    Web::set_template_variable("article", $formattedcontent);
    Web::set_template_variable("title", $title);
    Web::set_template_variable("contentdigest", $contentdigest);
    Web::set_template_variable("editreason", $editreason);
    Web::set_template_variable("editarticle", $markupcontent);

    if ( $err_msg ) {
        Web::set_template_variable("errorexists", "1");
        Web::set_template_variable("errormessage", $err_msg);
    }

    Web::display_page("Edit Content - " . $title);
    exit;
}

sub _update_blog_post {
    my $title         = shift;
    my $userid        = shift;
    my $markupcontent     = shift;
    my $formattedcontent     = shift;
    my $articleid       = shift;
    my $contentdigest = shift;
    my $editreason = shift;
    my $tag_list_str  = shift;

   #status = o p v d s

    my $new_status = 'o'; # default 
    if ( Utils::get_power_command_on_off_setting_for("draft", $markupcontent, 0) ) {
        $new_status = 'p'; # don't display in streams but do display in searches
    }

    if ( Utils::get_power_command_on_off_setting_for("private", $markupcontent, 0) ) {
        $new_status = 's'; # secret or private post
    }

    if ( Utils::get_power_command_on_off_setting_for("invisible", $markupcontent, 0) ) {
        $formattedcontent = " "; 
    }

    my $code_post = 0;
    if ( Utils::get_power_command_on_off_setting_for("code", $markupcontent, 0) ) {
        $code_post = 1;
        my $tmp_markupcontent = $markupcontent;
        $tmp_markupcontent =~ s/$title//;
        $tmp_markupcontent = Utils::remove_power_commands($tmp_markupcontent);
        $tmp_markupcontent = Utils::trim_spaces($tmp_markupcontent);
        $formattedcontent = HTML::Entities::encode($tmp_markupcontent, '<>');
#         $formattedcontent = "<pre>\n<code>\n" . $formattedcontent . "\n</code>\n</pre>\n";
        $formattedcontent = "<textarea class=\"codetext\" id=\"enhtextareaboxarticle\" rows=\"15\" cols=\"60\" wrap=\"off\" readonly>" . $formattedcontent  . "</textarea>\n";
    }           

    if ( !_is_updating_correct_article($articleid, $contentdigest) ) { 
        Web::report_error("user", "Error updating article.", "Access denied.");
    }

    if ( !user_owns_blog_post($articleid, $userid) ) {
         Web::report_error("user", "Invalid access.", "Unable to edit article.");
    }

    my $aid = $articleid;
    my $parentid = _is_updating_an_older_version($articleid);
    $aid = $parentid if ( $parentid > 0 );

    my $datetime = Utils::create_datetime_stamp();

    # 5jun2013 $tag_list_str = Utils::create_tag_list_str($markupcontent) if !$code_post;
    $tag_list_str = "" if $code_post;

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Web::report_error("system", "Error connecting to database.", $db->errstr) if $db->err;

    $title            = $db->quote($title);
    $markupcontent    = $db->quote($markupcontent);
    $formattedcontent = $db->quote($formattedcontent);
    $editreason       = $db->quote($editreason);
    my $quoted_tag_list_str     = $db->quote("|" . $tag_list_str . "|");

    my $sql;

    # make copy of most recent version.
    my %old;
    $sql =  "select id, title, markupcontent, formattedcontent, ";
    $sql .= "type, status, authorid, authorname, date, version, ";
    $sql .= "contentdigest, createdby, createddate, editreason, "; 
    $sql .= "tags, ipaddress ";
    $sql .= "from $dbtable_content where id=$aid";
    $db->execute($sql);
    Web::report_error("system", "(27) Error executing SQL", $db->errstr) if $db->err;
    
    if ( $db->fetchrow ) {
        $old{parentid}         = $db->getcol("id");
        $old{title}            = $db->quote($db->getcol("title"));
        $old{markupcontent}    = $db->quote($db->getcol("markupcontent"));
        $old{formattedcontent} = $db->quote($db->getcol("formattedcontent"));
        $old{type}             = $db->getcol("type");
        $old{status}           = $db->getcol("status");
        $old{authorid}         = $db->getcol("authorid");
        $old{authorname}       = $db->getcol("authorname");
        $old{date}             = $db->getcol("date");
        $old{version}          = $db->getcol("version");
        $old{contentdigest}    = $db->getcol("contentdigest");
        $old{createdby}        = $db->getcol("createdby");
        $old{createddate}      = $db->getcol("createddate");
        $old{editreason}       = $db->quote($db->getcol("editreason"));
        $old{tags}             = $db->quote($db->getcol("tags"));
        $old{ipaddress}        = $db->getcol("ipaddress");
    }
    Web::report_error("system", "Error retrieving data from database.", $db->errstr) if $db->err;

    my $status = 'v';  # previous version 
    $sql =  "insert into $dbtable_content (parentid, title, markupcontent, formattedcontent, type, status, authorid, authorname, date, version, contentdigest, createdby, createddate, editreason, tags, ipaddress)";
    $sql .= " values ($old{parentid}, $old{title}, $old{markupcontent}, $old{formattedcontent}, '$old{type}', '$status', $old{authorid}, '$old{authorname}', '$old{date}', $old{version}, '$old{contentdigest}', $old{createdby}, '$old{createddate}', $old{editreason}, $old{tags},  '$old{ipaddress}')";

    $db->execute($sql);
    Web::report_error("system", "(28) Error executing SQL", $db->errstr) if $db->err;

    #####  create new content digest when article updated??? for now, now.

    # add new modified content
    my $version = $old{version} + 1;
    $sql = "update $dbtable_content ";
    $sql .= " set title=$title, markupcontent=$markupcontent, formattedcontent=$formattedcontent, authorid=$userid, date='$datetime', status='$new_status', version=$version, editreason=$editreason, tags=$quoted_tag_list_str, ipaddress='$ENV{REMOTE_ADDR}' ";
    $sql .= " where id=$aid";
    $db->execute($sql);
    Web::report_error("system", "(29) Error executing SQL", $db->errstr) if $db->err;

    # removed existing tags from table
    $sql = "delete from $dbtable_tags where articleid=$articleid";
    $db->execute($sql);
    Web::report_error("system", "Error connecting to database.", $db->errstr) if $db->err;
    # remove beginning and ending pipe delimeter to make a proper delimited string
    $tag_list_str =~ s/^\|//;
    $tag_list_str =~ s/\|$//;
    my @tags = split(/\|/, $tag_list_str);
    foreach (@tags) {
        my $tag = $_;
        $tag = $db->quote($tag);
        if ( $tag ) {
            $sql = "insert into $dbtable_tags (name, articleid, type, status, createdby, createddate) "; 
            $sql .= " values ($tag, $articleid, 'b', 'o', $userid, '$datetime') "; 
            $db->execute($sql);
            Web::report_error("system", "(32-a) Error executing SQL", $db->errstr) if $db->err;
        }
    }

    $db->disconnect;
    Web::report_error("system", "Error disconnecting from database.", $db->errstr) if $db->err;

    return $aid;
}

sub _is_updating_correct_article {
    my ($articleid, $contentdigest) = @_;

    my $return_value = 0;

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Web::report_error("system", "Error connecting to database.", $db->errstr) if $db->err;

    $contentdigest = $db->quote($contentdigest);

    my $get_blog_post_edit_status = Config::get_value_for("get_blog_post_edit_status");

    my $sql = "select title from $dbtable_content ";
    $sql .=   "where id=$articleid and type in ('b') and status in ($get_blog_post_edit_status) and contentdigest=$contentdigest"; 
    $db->execute($sql);

    if ( $db->fetchrow ) {
        $return_value = 1;
    }
    Web::report_error("system", "Error retrieving data from database.", $db->errstr) if $db->err;

    $db->disconnect;
    Web::report_error("system", "Error disconnecting from database.", $db->errstr) if $db->err;

    return $return_value;
}

sub _is_updating_an_older_version {
    my $articleid = shift;

    my $parentid = 0;

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Web::report_error("system", "Error connecting to database.", $db->errstr) if $db->err;

    # if updating an older version, the parentid should be >0 and status should = v 
    my $sql = "select parentid from $dbtable_content where id=$articleid and type in ('b') and status='v'";
    $db->execute($sql);
    Web::report_error("system", "(62) Error executing SQL", $db->errstr) if $db->err;

    if ( $db->fetchrow ) {
        $parentid  = $db->getcol("parentid");
    }
    Web::report_error("system", "Error retrieving data from database.", $db->errstr) if $db->err;

    $db->disconnect;
    Web::report_error("system", "Error disconnecting from database.", $db->errstr) if $db->err;

    return $parentid;
}


sub _get_versions {
    my $articleid = shift;

    my $cgi_app = Config::get_value_for("cgi_app");

    my $offset = Utils::get_time_offset();

    my @loop_data; 

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Web::report_error("system", "Error connecting to database.", $db->errstr) if $db->err;

    my $sql = "select c.id,  ";
    $sql .=      "date_format(date_add(c.date, interval $offset hour), '%b %d, %Y') as date, ";
    $sql .=      "date_format(date_add(c.date, interval $offset hour), '%r') as time, ";
    $sql .=      "c.version, u.username, c.editreason from $dbtable_content c, $dbtable_users u ";
    $sql .=      "where c.parentid=$articleid and c.type in ('b') and c.status='v' and c.authorid=u.id ";
    $sql .=      "order by c.version desc";

    $db->execute($sql);
    Web::report_error("system", "(61) Error executing SQL", $db->errstr) if $db->err;

    my $cnt = 0;
    while ( $db->fetchrow ) {
        $cnt++;
        my %hash = ();
        $hash{articleid}       = $db->getcol("id");
        $hash{creationdate}    = $db->getcol("date");
        $hash{creationtime}    = lc($db->getcol("time"));
        $hash{version}         = $db->getcol("version");
        $hash{author}          = $db->getcol("username");
        $hash{editreason}      = $db->getcol("editreason");
        $hash{checked}         = "checked" if $cnt == 1;
        $hash{cgi_app}         = $cgi_app;
        push(@loop_data, \%hash);
    }
    Web::report_error("system", "Error retrieving data from database.", $db->errstr) if $db->err;

    $db->disconnect();
    Web::report_error("system", "Error disconnecting from database.", $db->errstr) if $db->err;

    return @loop_data;
}

sub _compare_versions {
    my $leftcontent  = shift;
    my $rightcontent = shift;

    my @loop_data = ();

    my @left  = split /[\n]/, $leftcontent;
    my @right = split /[\n]/, $rightcontent;

    # sdiff returns an array of arrays
    my @sdiffs = Algorithm::Diff::sdiff(\@left, \@right);

    # first element is the mod indicator.
    # second element contains a hunk of content from the or older version (left)
    # third element contains a hunk of content from the or newer version (right)
    # the mods are based upon how the right side (newer) compares to the left (older)

    # modification indicators
    #  'added'      => '+',
    #  'removed'    => '-',
    #  'unmodified' => 'u',
    #  'changed'    => 'c',

    foreach my $arref (@sdiffs) {
        my %hash = ();

        $hash{leftdiffclass}  = "unmodified";
        $hash{rightdiffclass} = "unmodified";

        if ( $arref->[0] eq '+' ) {
            $hash{rightdiffclass} = "added";
        } elsif ( $arref->[0] eq '-' ) {
            $hash{leftdiffclass}  = "removed";
        } elsif ( $arref->[0] eq 'c' ) {
            $hash{leftdiffclass}  = "changed";
            $hash{rightdiffclass} = "changed";
        }

        $hash{modindicator} = $arref->[0];
        
        $hash{left}       = encode_entities(Utils::trim_spaces($arref->[1]));
        $hash{right}      = encode_entities(Utils::trim_spaces($arref->[2]));

        $hash{left}  = "&nbsp;" if ( length($hash{left} ) < 1 );
        $hash{right} = "&nbsp;" if ( length($hash{right}) < 1 );

        push(@loop_data, \%hash);
    }

    return @loop_data;
}

sub _get_compare_info {
    my $leftid  = shift;
    my $rightid = shift;

    my $offset = Utils::get_time_offset();

    my %compare = ();

    my $left_authorid = 0;
    my $right_authorid = 0;

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Web::report_error("system", "Error connecting to database.", $db->errstr) if $db->err;

    my $sql = "select parentid, title, authorid, markupcontent, version, ";
    $sql .= "date_format(date_add(date, interval $offset hour), '%b %d, %Y') as date, ";
    $sql .= "date_format(date_add(date, interval $offset hour), '%r') as time ";
    $sql .= "from $dbtable_content where id=$leftid"; 
    $db->execute($sql);
    Web::report_error("system", "(68) Error executing SQL", $db->errstr) if $db->err;

    if ( $db->fetchrow ) {
        $compare{parentid}      = $db->getcol("parentid");
        $compare{title}         = $db->getcol("title");
        $left_authorid          = $db->getcol("authorid");
        $compare{urltitle}      = Utils::clean_title($compare{title});
        $compare{leftcontent}   = $db->getcol("markupcontent");
        $compare{leftversion}   = $db->getcol("version");
        $compare{leftdate}      = $db->getcol("date");
        $compare{lefttime}      = lc($db->getcol("time"));
    }
    Web::report_error("system", "Error retrieving data from database.", $db->errstr) if $db->err;

    $sql = "select authorid, markupcontent, version, "; 
    $sql .= "date_format(date_add(date, interval $offset hour), '%b %d, %Y') as date, ";
    $sql .= "date_format(date_add(date, interval $offset hour), '%r') as time ";
    $sql .= "from $dbtable_content where id=$rightid";
    $db->execute($sql);
    Web::report_error("system", "(69) Error executing SQL", $db->errstr) if $db->err;

    if ( $db->fetchrow ) {
        $right_authorid          = $db->getcol("authorid");
        $compare{rightcontent}   = $db->getcol("markupcontent");
        $compare{rightversion}   = $db->getcol("version");
        $compare{rightdate}      = $db->getcol("date");
        $compare{righttime}      = lc($db->getcol("time"));
    }

    $db->disconnect;
    Web::report_error("system", "Error disconnecting from database.", $db->errstr) if $db->err;

    # currently, only one person can edit a blog post. 
    # maybe later, multi-authoring will be permitted.
    if ( $right_authorid != $left_authorid ) {
        %compare = ();
    } else {
        my $is_users_blog_post = user_owns_blog_post($compare{parentid}, $right_authorid);
        if ( _is_top_level_post_private($compare{parentid}) and !$is_users_blog_post ) {
            %compare = ();
        } elsif ( Utils::get_power_command_on_off_setting_for("private", $compare{leftcontent}, 0) and !$is_users_blog_post ) {
            %compare = ();
        } elsif ( Utils::get_power_command_on_off_setting_for("private", $compare{rightcontent}, 0) and !$is_users_blog_post ) {
            %compare = ();
        }
    }
 
    return %compare;
}

sub _title_exists {
    my $new_article_title = shift;

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Utils::report_error("system", "Error connecting to database.", $db->errstr) if $db->err;

    $new_article_title = $db->quote($new_article_title);

    my $sql = "select id from $dbtable_content where title=$new_article_title"; 
    $db->execute($sql);
    Utils::report_error("system", "(63) Error executing SQL", $db->errstr) if $db->err;

    my $title_already_exists = 0;

    if ( $db->fetchrow ) {
        $title_already_exists = 1; 
    } else {
        $sql = "select id from $dbtable_users where username=$new_article_title";
        $db->execute($sql);
        Utils::report_error("system", "(63) Error executing SQL", $db->errstr) if $db->err;
        if ( $db->fetchrow ) {
            $title_already_exists = 1; 
        }
    }
    Web::report_error("system", "Error retrieving data from database.", $db->errstr) if $db->err;

    $db->disconnect;
    Web::report_error("system", "Error disconnecting from database.", $db->errstr) if $db->err;

    return $title_already_exists;
}

# related article SQL from Pete Freitag's blog post at
# http://www.petefreitag.com/item/315.cfm
sub _get_related_articles {
    my $articleid = shift;
    my $tags      = shift;

    my $cgi_app = Config::get_value_for("cgi_app");

    my $offset = Utils::get_time_offset();

    # if at least one tag, then string will contain at a minimum
    #     |x|
    my @loop_data = ();
    return @loop_data if ( !$tags or (length($tags) < 3) );

    my @tagnames = ();
    my $instr = "";
    $tags =~ s/^\|//;
    $tags =~ s/\|$//;
    if ( @tagnames = split(/\|/, $tags) ) {
        foreach (@tagnames) {
            $instr .= "'$_'," if ( $_ );
        }
    }
    $instr =~ s/,$//;

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Web::report_error("system", "Error connecting to database.", $db->errstr) if $db->err;

    my $sql = <<EOSQL; 
    SELECT c.id, c.title,
      DATE_FORMAT(DATE_ADD(c.date, interval $offset hour), '%b %d, %Y') AS date,
      COUNT(m.articleid) AS wt
      FROM $dbtable_content AS c, $dbtable_tags AS m
      WHERE m.articleid <> $articleid 
      AND m.name IN ($instr)
      AND c.id = m.articleid
      AND c.status in ('o')  
      AND c.type in ('b')
      GROUP BY c.title, c.id
      HAVING wt > 1
      ORDER BY wt DESC 
EOSQL

    $db->execute($sql);
    Web::report_error("system", "(66) Error executing SQL", $db->errstr) if $db->err;

    while ( $db->fetchrow ) {
        my %hash;
        $hash{articleid}     = $db->getcol("id");
        $hash{title}         = $db->getcol("title");
        $hash{urltitle}      = Utils::clean_title($hash{title});
        $hash{date}          = $db->getcol("date");
        $hash{cgi_app}       = $cgi_app;
        push(@loop_data, \%hash);
    }
    Web::report_error("system", "Error retrieving data from database.", $db->errstr) if $db->err;

    $db->disconnect;
    Web::report_error("system", "Error disconnecting from database.", $db->errstr) if $db->err;

    return @loop_data;
}

sub _create_table_of_contents {
    my $str = shift;

    my @headers = ();
    my @loop_data = ();

    if ( @headers = $str =~ m{<!-- header:([1-6]):(.*?) -->}igs ) {
        my $len = @headers;
        for (my $i=0; $i<$len; $i+=2 ) {
            my %hash = ();
            $hash{level}      = $headers[$i];
            $hash{toclink}    = $headers[$i+1];
            $hash{cleantitle} = Utils::clean_title($headers[$i+1]);
            push(@loop_data, \%hash); 
        }
    }

    return @loop_data;    
}

sub _get_blog_post_id {
    my $title = shift;

    my $blog_post_id = 0;

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Web::report_error("system", "Error connecting to database.", $db->errstr) if $db->err;

    $title = $db->quote($title);

    my $sql = "select id from $dbtable_content where title=$title and type='b' and status='o' limit 1";

    $db->execute($sql);
    Web::report_error("system", "(77) Error executing SQL", $db->errstr) if $db->err;

    if ( $db->fetchrow ) {
        $blog_post_id = $db->getcol("id");
    }
    Web::report_error("system", "Error retrieving data from database.", $db->errstr) if $db->err;

    $db->disconnect;
    Web::report_error("system", "Error disconnecting from database.", $db->errstr) if $db->err;

    return $blog_post_id;
}

sub _include_templates {
    my $str = shift;

    while ( $str =~ m/{{(.*?)}}/ ) {
        my $title = $1;
        my $include = "";
        if ( $title =~ m|^feed=h(.*?)://(.*?)$|i ) {
            my $rssurl = "h" . $1 . "://" .  $2;
            $include = Utils::get_rss_feed($rssurl);
        } 
        else {
            $include = _get_formatted_content_for_template($title);
            if ( !$include ) {
                $include = "**Include template \"$title\" not found.**";
            }
        }
        my $old_str = "{{$title}}";
        $str =~ s/\Q$old_str/$include/;
    }

    return $str;
}

sub _get_formatted_content_for_template {
    my $orig_str = shift;

    $orig_str = Utils::trim_spaces($orig_str);

    my $str;

    if ( $orig_str !~ m /^Template:/i ) {
        $str = "Template:" . $orig_str;
    } else {
        $str = $orig_str;
    }    

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Web::report_error("system", "Error connecting to database.", $db->errstr) if $db->err;

    my $title            = $db->quote($str);

    my $sql = "select formattedcontent from $dbtable_content where title = $title and status in ('o') and type in ('b')";
    $db->execute($sql);
    Web::report_error("system", "(72) Error executing SQL", $db->errstr) if $db->err;

    my $formattedcontent = "";

    if ( $db->fetchrow ) {
        $formattedcontent = $db->getcol("formattedcontent");
    } else {
        $title            = $db->quote($orig_str);
        $sql = "select formattedcontent from $dbtable_content where title = $title and status in ('o') and type in ('b')";
        $db->execute($sql);
        Web::report_error("system", "(72) Error executing SQL", $db->errstr) if $db->err;
        if ( $db->fetchrow ) {
            $formattedcontent = $db->getcol("formattedcontent");
        }
    }
    Web::report_error("system", "Error retrieving data from database.", $db->errstr) if $db->err;

    $db->disconnect;
    Web::report_error("system", "Error disconnecting from database.", $db->errstr) if $db->err;

    if ( $formattedcontent =~ m/<tmpl>(.*?)<\/tmpl>/is ) {
        $formattedcontent = Utils::trim_br($1);
        $formattedcontent = Utils::trim_spaces($formattedcontent);
    }  

    return $formattedcontent;
}

sub kdebug {
    my $str = shift;
    Web::report_error("user", "debug", $str);
}

sub user_owns_blog_post {
    my $articleid = shift;
    my $authorid  = shift;

    return 0 if !Utils::is_numeric($articleid);

    return 0 if !Utils::is_numeric($authorid);

    return 0 if $articleid < 1 or $authorid < 1;

        # get value from user's browser cookie
    my $logged_in_userid       = User::get_logged_in_userid();

        # the logged in user must equal the blog post author
    return 0 if $logged_in_userid ne $authorid;

        # User::valid_user compares logged in user's cookie info with what's stored in the database for the userid.
        # the username, userid, and digest from the browser cookies and database are compared in User::valid_user and they must equal.
    return 0 if !User::valid_user();

        # the logged in user's browser cookies equals info stored in user database table and 
        # the logged in user equals the author of the blog post
    return 1;
}

sub  _is_top_level_post_private {
    my $articleid = shift;

    my $return_status = 1;  # default to private
 
    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Web::report_error("system", "Error connecting to database.", $db->errstr) if $db->err;

    my $sql = "select markupcontent from $dbtable_content where id=$articleid"; 

    $db->execute($sql);
    Web::report_error("system", "(31-a) Error executing SQL", $db->errstr) if $db->err;

    if ( $db->fetchrow ) {
        my $tmp_markup         = $db->getcol("markupcontent");
        if ( !Utils::get_power_command_on_off_setting_for("private", $tmp_markup, 0) ) {
            $return_status = 0;
        }
    }
    Web::report_error("system", "Error retrieving data from database.", $db->errstr) if $db->err;

    $db->disconnect();
    Web::report_error("system", "Error disconnecting from database.", $db->errstr) if $db->err;

    return $return_status;
}

sub get_blog_post_count {
    my $status = shift;

    User::user_allowed_to_function();

    my $logged_in_userid = User::get_logged_in_userid();

    my $blog_count =0;

    return $blog_count if !$logged_in_userid; 

    return $blog_count if $status ne "s" and $status ne "p";

    my $db = Db->new($pt_db_catalog, $pt_db_user_id, $pt_db_password);
    Web::report_error("system", "Error connecting to database.", $db->errstr) if $db->err;

    my $sql;

    $sql = "select count(*) as blogcount from $dbtable_content where type='b' and status='$status' and authorid=$logged_in_userid"; 

    $db->execute($sql);
    Web::report_error("system", "(F61d) Error executing SQL", $db->errstr) if $db->err;

    if ( $db->fetchrow ) {
        $blog_count = $db->getcol("blogcount");
    }
    Web::report_error("system", "Error retrieving data from database.", $db->errstr) if $db->err;

    $db->disconnect();
    Web::report_error("system", "Error disconnecting from database.", $db->errstr) if $db->err;

    return $blog_count;
}


1;
