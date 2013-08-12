package Blog;

use strict;

use HTML::Entities;
use Kestrel::BlogData;
use Kestrel::Backlinks;
use Kestrel::Likes;

sub show_blog_post_form {
    User::user_allowed_to_function();
    Web::set_template_name("blogpostform");
    Web::display_page("Blog Post Form");
}

sub show_enhanced_blog_post_form {
    User::user_allowed_to_function();
    Web::set_template_name("enhblogpostform");
    Web::display_page("Enhanced Blog Post Form");
}

sub show_textile_editor_form {
    User::user_allowed_to_function();
    Web::set_template_name("textileeditor");
    Web::display_page_min("Textile Editor Blog Post Form");
}

sub show_blog_source {
    my $tmp_hash = shift;  

    my $articleid = $tmp_hash->{one}; 

    if ( !defined($articleid)  or !$articleid or $articleid !~ /^[0-9]+$/ ) {
        Web::report_error("user", "Invalid input", "Missing or invalid article id: $articleid.");
    }

    my %article_data = BlogData::_get_blog_source($articleid);

    if ( !%article_data ) {
        Web::report_error("user", "Invalid article access.", "Data doesn't exist.") 
    }

    my $markupcontent = $article_data{markupcontent};
    $markupcontent = encode_entities($markupcontent, '<>&');
    $markupcontent = Utils::newline_to_br($markupcontent);

    Web::set_template_name("blogsource");
    Web::set_template_variable("id",            $articleid);
    Web::set_template_variable("title",         $article_data{title});
    Web::set_template_variable("cleantitle",    Utils::clean_title($article_data{title}));
    Web::set_template_variable("markupcontent", $markupcontent);
    Web::display_page("Blog post source for: $article_data{title}");
}

sub show_blog_post {
    my $tmp_hash = shift;  

    my $articleid = $tmp_hash->{one}; 

    my $canedit = 0;

    if ( !defined($articleid)  or !$articleid or $articleid !~ /^[0-9]+$/ ) {
        Web::report_error("user", "Invalid input", "Missing or invalid article id: $articleid.");
    }

    my %blog_post = BlogData::_get_blog_post($articleid);

    Web::report_error("user", "Invalid article access.", "Data doesn't exist.") if ( !%blog_post );

    Web::set_template_name("blogpost");

    if ( $blog_post{redirectedpage} ) {
        Web::set_template_variable("redirectedpage", 1);
        Web::set_template_variable("originalid", $blog_post{originalid});
        Web::set_template_variable("originaltitle", $blog_post{originaltitle});
    } 

    # make include templates dynamic. a change in the template automatic takes affect at display time in every article using the template.
    $blog_post{blogpost} = BlogData::_include_templates($blog_post{blogpost});

    Web::set_template_variable("authorname",    $blog_post{authorname});
    Web::set_template_variable("cgi_app",       $blog_post{cgi_app});
    Web::set_template_variable("articleid",     $blog_post{articleid});
    Web::set_template_variable("cleantitle",    $blog_post{cleantitle});
    Web::set_template_variable("urldate",       $blog_post{urldate});
    Web::set_template_variable("title",         $blog_post{title});
    Web::set_template_variable("blogpost",      $blog_post{blogpost});
    Web::set_template_variable("createddate",   $blog_post{createddate});
    Web::set_template_variable("createdtime",   $blog_post{createdtime});

#     Web::set_template_variable("likecount",     Likes::get_like_count($articleid));
    Web::set_template_variable("likes",     $blog_post{likes});
    Web::set_template_variable("islikedbyuser", Likes::is_post_liked_by_user($articleid));

    my $logged_in_username = User::get_logged_in_username();
    my $logged_in_userid   = User::get_logged_in_userid();
    if ( $logged_in_userid > 0 and User::valid_user() and ($logged_in_username eq $blog_post{authorname})  ) {
        Web::set_template_variable("canedit", 1);
        $canedit = 1;
    }

    if ( $blog_post{updated} ) {
        Web::set_template_variable("updated", 1);
        Web::set_template_variable("modifieddate",   $blog_post{modifieddate});
        Web::set_template_variable("modifiedtime",   $blog_post{modifiedtime});
    }

    if ( $blog_post{status} eq "v" ) {
        Web::set_template_variable("versionlinkarticleid", $blog_post{parentid});
        Web::set_template_variable("viewingoldversion", 1);
        Web::set_template_variable("versionnumber", $blog_post{version});
    } elsif ( $blog_post{status} eq "o" and ($blog_post{parentid} > 0) and ($blog_post{hidereply} eq "n") ) {
        my %replytohash = Reply::get_parent_blog_info($blog_post{parentid});
        Web::set_template_variable("isreplyblogpost", 1);
        Web::set_template_variable("replytoid", $blog_post{parentid});
        Web::set_template_variable("replytotitle", $replytohash{replytotitle});
    }

    if ( $blog_post{usingimageheader} ) {
        Web::set_template_variable("usingimageheader", 1);
        Web::set_template_variable("imageheaderurl", $blog_post{imageheaderurl});
    }

    if ( $blog_post{usinglargeimageheader} ) {
        Web::set_template_variable("usinglargeimageheader", 1);
        Web::set_template_variable("largeimageheaderurl", $blog_post{largeimageheaderurl});
    }

    Web::set_template_variable("wordcount", $blog_post{words});
    Web::set_template_variable("charcount", $blog_post{chars});
    Web::set_template_variable("readingtime", $blog_post{readingtime});

    my @loop_data = ();
    @loop_data = BlogData::_get_related_articles($articleid, $blog_post{tags});
    if ( @loop_data ) {
        Web::set_template_variable("relatedarticlesexist", 1);
        my $len = @loop_data;
        if ( $len > 5 ) {
            Web::set_template_variable("morerelatedarticles", 1);
            for (my $i=$len; $i>5; $i--) {
                pop(@loop_data);
            } 
        }
        Web::set_template_loop_data("relatedarticles", \@loop_data);
    }

    if ( $blog_post{toc} ) {
        my @toc_loop = BlogData::_create_table_of_contents($blog_post{blogpost});
        if ( @toc_loop ) {
            Web::set_template_variable("usingtoc", "1");
            Web::set_template_loop_data("toc", \@toc_loop);
        }    
    }

    if ( Backlinks::backlinks_exist($articleid) ) {
        Web::set_template_variable("backlinks", 1);
    }

    my @blog_replies;
    if ( @blog_replies = Reply::replies_exist($articleid, $canedit) ) {
        Web::set_template_variable("replies", 1);
        Web::set_template_loop_data("blogreplies", \@blog_replies);
    }
   
    if ( Reply::allowed_to_reply($articleid, $logged_in_userid ) ) {
        Web::set_template_variable("allowedtoreply", 1);
    }
    
    Web::set_template_variable("contentdigest", $blog_post{contentdigest});

    Web::display_page($blog_post{title}); 
}

sub show_related_blog_posts {
    my $tmp_hash = shift;  

    my $articleid = $tmp_hash->{one};

    my %blog_post = BlogData::_get_blog_post($articleid);

    my @loop_data = ();
    @loop_data = BlogData::_get_related_articles($articleid, $blog_post{tags});

    Web::set_template_name("relatedblogposts");
    Web::set_template_variable("title", $blog_post{title});
    Web::set_template_variable("cleantitle",    $blog_post{cleantitle});
    Web::set_template_variable("articleid", $articleid);
    Web::set_template_loop_data("relatedarticles",  \@loop_data);

    Web::display_page("Backlinks for $blog_post{title}");
}

sub add_blog_post {

    my $q = new CGI;
    my $err_msg = "";
   
    User::user_allowed_to_function();

    my $formattedcontent = "";
    my $posttitle = "";
    my $replyblogpost = 0;

    my $replytocontentdigest = $q->param("replytocontentdigest");
    if ( $replytocontentdigest ) {
        $replyblogpost = 1;
    }

    my $markupcontent = $q->param("article");
    if ( !defined($markupcontent) || length($markupcontent) < 1 ) {
        $err_msg .= "You must enter content.<br /><br />";
    }

    my $sb = $q->param("sb");
    if ( !defined($sb) || length($sb) < 1 ) {
        $err_msg .= "Missing the submit button value.<br /><br />";
    }

    my $formtype = $q->param("formtype");

    my $title = $markupcontent;
    my $tmp_markupcontent;

    my $max_title_len = Config::get_value_for("max_blog_post_title_length");
    if ( $title =~ m/(.+)/ ) {
        my $tmp_title = $1;
        if ( length($tmp_title) < $max_title_len+1  ) {
            my $tmp_title_len = length($tmp_title);
            $title = $tmp_title;
            my $tmp_total_len = length($markupcontent);
            $tmp_markupcontent = substr $markupcontent, $tmp_title_len, $tmp_total_len - $tmp_title_len;
        } else {
            $title = substr $markupcontent, 0, $max_title_len;
            my $tmp_total_len = length($markupcontent);
            $tmp_markupcontent = substr $markupcontent, $max_title_len, $tmp_total_len - $max_title_len;
        }   
    }

    if ( !defined($title) || length($title) < 1 ) {
        $err_msg .= "You must give a title for your article.<br /><br />";
    } else {
        if ( BlogData::_title_exists(Utils::trim_spaces($title)) ) {
            $err_msg .= "Article title: \"$title\" already exists. Choose a different title.<br /><br />";
        }
    }

    $posttitle     = Utils::trim_spaces($title);
    $posttitle     = ucfirst($posttitle);
    $posttitle     = encode_entities($posttitle, '<>');

    my $tag_list_str = Utils::create_tag_list_str($markupcontent);
    # remove beginning and ending pipe delimeter to make a proper delimited string
    $tag_list_str =~ s/^\|//;
    $tag_list_str =~ s/\|$//;
    my @tags = split(/\|/, $tag_list_str);
    my $tmp_tag_len = @tags;
    my $max_unique_hashtags = Config::get_value_for("max_unique_hashtags");
    if ( $tmp_tag_len > $max_unique_hashtags ) {
        $err_msg .= "Sorry. Only 7 unique hashtags are permitted.";
    }

    $err_msg = Utils::check_for_special_tag($err_msg, $tag_list_str); 

    if ( $err_msg ) {
        $formattedcontent = Utils::format_content($tmp_markupcontent);
        $formattedcontent = BlogData::_include_templates($formattedcontent);
        BlogData::_preview_article($title, $markupcontent, $posttitle, $formattedcontent, $err_msg, $replyblogpost, $replytocontentdigest, $formtype);
    } 

    my $clean_title   = Utils::clean_title($posttitle);

    $formattedcontent = Utils::format_content($tmp_markupcontent);

    if ( $sb eq "Preview" ) {
        $formattedcontent = BlogData::_include_templates($formattedcontent);
        BlogData::_preview_article($title, $markupcontent, $posttitle, $formattedcontent, $err_msg, $replyblogpost, $replytocontentdigest, $formtype);
    }

    my $logged_in_userid   = User::get_logged_in_userid();

    my $articleid = BlogData::_add_blog($posttitle, $logged_in_userid, $markupcontent, $formattedcontent, $replyblogpost, $replytocontentdigest, $tag_list_str);

    my @backlinks = Backlinks::get_backlink_ids($formattedcontent);
    Backlinks::add_backlinks($articleid, \@backlinks) if @backlinks;

    my $url = Config::get_value_for("cgi_app") . "/blogpost/$articleid/$clean_title";
    print $q->redirect( -url => $url);
}

sub enhanced_edit_blog_post {
    my $tmp_hash = shift;
    
    $tmp_hash->{formtype} = "enhanced";
    edit_blog_post($tmp_hash);
}

sub edit_blog_post {
    my $tmp_hash = shift;  

    my $articleid = $tmp_hash->{one};

    my $enhanced = 0;
    $enhanced = 1 if $tmp_hash->{formtype} eq "enhanced";

    User::user_allowed_to_function();

    my $userid     = User::get_logged_in_userid();
    my $sessionid  = User::get_logged_in_sessionid();

    my %article_data = BlogData::_get_blog_post_for_edit($userid, $articleid, $sessionid);

    if ( $enhanced ) {
        Web::set_template_name("enheditblogpostform");
    } else { 
        Web::set_template_name("editblogpostform");
    }

    Web::set_template_variable("articleid", $article_data{articleid});

    Web::set_template_variable("title", encode_entities($article_data{title}));

    Web::set_template_variable("article", $article_data{formatted}) if $enhanced;

    $article_data{markup} = encode_entities($article_data{markup}, '<>&');

    Web::set_template_variable("editarticle", $article_data{markup});

    Web::set_template_variable("contentdigest", $article_data{contentdigest});

    if ( $article_data{status} eq "v" ) {  
        Web::set_template_variable("viewingoldversion", 1);
        Web::set_template_variable("versionnumber", $article_data{versionnumber});
        Web::set_template_variable("parentid", $article_data{parentid});
        Web::set_template_variable("cleantitle", Utils::clean_title($article_data{title}));
        $article_data{title} .= " (older version) ";
    }

    Web::display_page("Edit Content - " . $article_data{title});
}

sub update_blog_post {
    my $q = new CGI;
    my $err_msg = "";

    my $formattedcontent = "";
    my $posttitle = "";

    User::user_allowed_to_function();

    my $articleid = $q->param("articleid");
    if ( !defined($articleid) || length($articleid) < 1 ) {
        $err_msg .= "Content id missing.<br /><br />";
    }

    my $contentdigest = $q->param("contentdigest");
    if ( !defined($contentdigest) || length($contentdigest) < 1 ) {
        $err_msg .= "Missing content digest.<br /><br />";
    }

    my $markupcontent = $q->param("markupcontent");
    if ( !defined($markupcontent) || length($markupcontent) < 1 ) {
        $err_msg .= "You must enter content.<br /><br />";
    }

    my $editreason = $q->param("editreason");
    $editreason    = encode_entities($editreason, '<>');

    my $sb = $q->param("sb");
    if ( !defined($sb) || length($sb) < 1 ) {
        $err_msg .= "Missing the submit button value.<br /><br />";
    }

    my $formtype = $q->param("formtype");

    my $title = $markupcontent;
    my $tmp_markupcontent;

    my $max_title_len = Config::get_value_for("max_blog_post_title_length");
    if ( $title =~ m/(.+)/ ) {
        my $tmp_title = $1;
        if ( length($tmp_title) < $max_title_len+1  ) {
            my $tmp_title_len = length($tmp_title);
            $title = $tmp_title;
            my $tmp_total_len = length($markupcontent);
            $tmp_markupcontent = substr $markupcontent, $tmp_title_len, $tmp_total_len - $tmp_title_len;
        } else {
            $title = substr $markupcontent, 0, $max_title_len;
            my $tmp_total_len = length($markupcontent);
            $tmp_markupcontent = substr $markupcontent, $max_title_len, $tmp_total_len - $max_title_len;
        }   
    }

    if ( !defined($title) || length($title) < 1 ) {
        $err_msg .= "You must give a title for your article.<br /><br />";
    } 
#    else {
#        if ( BlogData::_title_exists(Utils::trim_spaces($title)) ) {
#            $err_msg .= "Article title: \"$title\" already exists. Choose a different title.<br /><br />";
#        }
#    }

    $posttitle     = Utils::trim_spaces($title);
    $posttitle     = ucfirst($posttitle);
    $posttitle     = encode_entities($posttitle, '<>');

    my $tag_list_str = Utils::create_tag_list_str($markupcontent);
    # remove beginning and ending pipe delimeter to make a proper delimited string
    $tag_list_str =~ s/^\|//;
    $tag_list_str =~ s/\|$//;
    my @tags = split(/\|/, $tag_list_str);
    my $tmp_tag_len = @tags;
    my $max_unique_hashtags = Config::get_value_for("max_unique_hashtags");
    if ( $tmp_tag_len > $max_unique_hashtags ) {
        $err_msg .= "Sorry. Only 7 unique hashtags are permitted.";
    }

    $err_msg = Utils::check_for_special_tag($err_msg, $tag_list_str); 

    if ( $err_msg ) {
        $markupcontent = encode_entities($markupcontent, '<>&');
        BlogData::_preview_edit($title, $markupcontent, $posttitle, $formattedcontent, $articleid, $contentdigest, $editreason, $err_msg, $formtype);
    } 

    my $clean_title   = Utils::clean_title($posttitle);

    $formattedcontent = Utils::format_content($tmp_markupcontent);

    if ( $sb eq "Preview" ) {
        $formattedcontent = BlogData::_include_templates($formattedcontent);
        $markupcontent = encode_entities($markupcontent, '<>&');
        BlogData::_preview_edit($title, $markupcontent, $posttitle, $formattedcontent, $articleid, $contentdigest, $editreason, $err_msg, $formtype);
    } 
    elsif ( $sb ne "Update" ) {
        Web::report_error("user", "Unable to update article.", "Invalid action: $sb");
    }

    my $logged_in_userid   = User::get_logged_in_userid();
    my $aid = BlogData::_update_blog_post($posttitle, $logged_in_userid, $markupcontent, $formattedcontent, $articleid, $contentdigest, $editreason, $tag_list_str);
 
    my @backlinks = Backlinks::get_backlink_ids($formattedcontent);
    Backlinks::add_backlinks($aid, \@backlinks) if @backlinks;
     
    my $url = Config::get_value_for("cgi_app") . "/blogpost/$aid/$clean_title";
    print $q->redirect( -url => $url);
}

sub show_version_list {
    my $tmp_hash = shift;  

    my $articleid = $tmp_hash->{one}; 

    if ( !$articleid or !Utils::is_numeric($articleid) ) {
        Web::report_error("user", "Invalid version access.", "Missing blog post id");
    } 

    my %article_data = BlogData::_get_blog_post($articleid);
    if ( !%article_data ) {
        Web::report_error("user", "Invalid version access.", "Data doesn't exist");
    }

    if ( BlogData::_is_top_level_post_private($articleid) and !BlogData::user_owns_blog_post($articleid, $article_data{authorid}) ) {
        Web::report_error("user", "Invalid version access.", "Data doesn't exist");
    }

    my @loop_data = BlogData::_get_versions($articleid);
    if ( !@loop_data ) {
        Web::report_error("user", "Invalid version access.", "Data doesn't exist");
    }

    my $len = @loop_data;
    Web::set_template_name("versions");

    Web::set_template_variable("title",               $article_data{title});    
    Web::set_template_variable("titleurl",            $article_data{cleantitle}); 
    Web::set_template_variable("currentarticleid",    $article_data{articleid});   
    Web::set_template_variable("currentversion",      $len+1);
    Web::set_template_variable("currentauthor",       $article_data{authorname});
    Web::set_template_variable("currentcreationdate", $article_data{modifieddate});   
    Web::set_template_variable("currentcreationtime", $article_data{modifiedtime});   
    Web::set_template_variable("currenteditreason",   $article_data{editreason});   

    Web::set_template_loop_data("versions", \@loop_data);
    Web::display_page("Versions");
}

sub compare_versions {
    my $q = new CGI;
    my $leftid  = $q->param("leftid");
    my $rightid = $q->param("rightid");
    if ( !$leftid or !$rightid ) {
        Web::report_error("user", "Invalid comparison.", "Can't compare with itself.");
    }

    my %compare = BlogData::_get_compare_info($leftid, $rightid);
    if ( !%compare ) {
        Web::report_error("user", "Invalid comparison.", "Cannot access one more posts.");
    }
    
    Web::set_template_name("compare");
    Web::set_template_variable("leftversionid",  $leftid);
    Web::set_template_variable("rightversionid",  $rightid);
    Web::set_template_variable("title",        $compare{title});
    Web::set_template_variable("urltitle",     $compare{urltitle});
    Web::set_template_variable("parentid",     $compare{parentid});
    Web::set_template_variable("leftversion",  $compare{leftversion});
    Web::set_template_variable("rightversion", $compare{rightversion});
    Web::set_template_variable("leftdate",  $compare{leftdate});
    Web::set_template_variable("lefttime",  $compare{lefttime});
    Web::set_template_variable("rightdate", $compare{rightdate});
    Web::set_template_variable("righttime", $compare{righttime});

    my @loop_data = BlogData::_compare_versions($compare{leftcontent}, $compare{rightcontent});
    
    Web::set_template_loop_data("compare", \@loop_data);
    Web::display_page("$compare{title}: Comparing versions $compare{leftversion} and $compare{rightversion}");
}

sub delete_blog {
    my $tmp_hash = shift;  

    my $articleid = $tmp_hash->{one}; 

    User::user_allowed_to_function();

    my $q = new CGI;

    BlogData::_delete_blog_post(User::get_logged_in_userid(), $articleid);
    # 23may2013 print $q->redirect( -url => $ENV{HTTP_REFERER});
    # 5jun2013 my $url = Config::get_value_for("home_page");
    # 5june2013 print $q->redirect( -url => $url);
    print $q->redirect( -url => $ENV{HTTP_REFERER});
}

sub undelete_blog {
    my $tmp_hash = shift;  

    my $articleid = $tmp_hash->{one}; 

    User::user_allowed_to_function();

    my $q = new CGI;

    BlogData::_undelete_blog_post(User::get_logged_in_userid(), $articleid);
    # 23may2023 print $q->redirect( -url => $ENV{HTTP_REFERER});
    # 5jun2013 my $url = Config::get_value_for("home_page");
    # 5jun2013 print $q->redirect( -url => $url);
    print $q->redirect( -url => $ENV{HTTP_REFERER});
}

sub kdebug {
    my $str = shift;
    Web::report_error("user", "debug", $str);
}

1;

