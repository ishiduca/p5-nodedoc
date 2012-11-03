package App::Nodedoc;
use Dancer ':syntax';

our $VERSION = '0.1';

use Nodedoc;
use Text::Markdown 'markdown';

set home => "$ENV{HOME}"; # set start to scanning directory

get '/' => sub {
    template 'index', {
        home => setting('home'),
    };
};

get '/not/found/file' => sub {
    template 'not_found_file', {
        file => param 'path',
    };
};

get '/list' => sub {
    my $start_dir = param 'start_dir';

    unless (-d $start_dir) {
        redirect "/not/found/file?path=$start_dir", 301;
        return;
    }

    my $nd      = Nodedoc->new( $start_dir );
    my $modules = $nd->make_modules_list->modules;
    my @mods    = ();
    for my $mod_name (sort{ uc $a cmp uc $b } keys %{$modules}) {
        my $mod = $nd->module( $mod_name );
        my $version = $mod->{version} ? $mod->{version} : 'verion.not.found';
        my $main    = $mod->{main}    ? $mod->{main}    : '';
        my $package_json = ($mod->{package_json} && $mod->{package_json}{file})
                         ? $mod->{package_json}{file} : '';
        my $readme = ($mod->{readme} && $mod->{readme}{file})
                   ? $mod->{readme}{file} : '';

        push @mods, {
            mod_name     => $mod_name,
            main         => $main,
            version      => $version,
            package_json => $package_json,
            readme       => $readme,
        };
    }

    template 'list', {
        start_dir => $start_dir,
        mods      => [ @mods ]
    };
};

sub _send_file {
    my $file = param 'path';

    unless (-f $file && -s _) {
        redirect "/not/found/file?path=$file" , 301;
        return;
    }

	if (request->uri =~ /readme/) {
        my $md = markdown do {
            local $/;
            open my $fh, '<', $file or send_error($!) and return;
            <$fh>;
        };

        return send_file( \$md, content_type => 'text/html');
	}

    send_file( $file, system_path => 1 );
}

get '/main'         => \&_send_file;
get '/package_json' => \&_send_file;
get '/readme'       => \&_send_file;

true;
