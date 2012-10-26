package Nodedoc;
use strict;
use warnings;
use 5.008001;

our $VERSION = '0.01';

use File::Basename qw(dirname);

sub new {
    my $class     = shift;
    my $start_dir = Nodedoc::Find::resolve( shift || '.' );
    bless {
        home      => $ENV{HOME},
        start_dir => $start_dir,
        modules   => {},
        @_,
    }, $class;
}

sub _do_loop {
    my($self, $cb, $deep) = @_;
    my $here = $self->{start_dir};
    my $home = File::Basename::dirname($self->{home});
    my $loop_stop;

    while ($here ne $home && ! $loop_stop) {
        Nodedoc::Find::find_node_modules( $here => sub {
            my $mod = shift;
            return if $self->module( $mod->{name} );
            $self->module( $mod->{name} => $mod );

            if ($cb and ref $cb eq 'CODE' and my $stop = $cb->($mod)) {
                if ($stop) {
                    $loop_stop = ! $loop_stop;
                    return $stop;
                }
            }
        });

        last if $deep;

        $here = File::Basename::dirname($here);
    }

    $self;
}

sub make_modules_list { my $self = shift; $self->_do_loop; $self }
sub make_modules_tree {
    my $self = shift;
    my $next; $next = sub {
        my($mod, $parent) = @_;
        return if ! $mod->{main};
        $parent->{dependences} or $parent->{dependences} = +{};
        return if $parent->{dependences}{$mod->{name}};
        $parent->{dependences}{$mod->{name}} = $mod;
        return if $mod->{main} =~ m: / node_modules
                                     / $mod->{name}\.(js|node|json)$
                                  :x;
        my $dir = ($mod->{main} =~ m: ^( .+
                                         / node_modules
                                         / $mod->{name}
                                       ).* $
                                   :x)[-1];

        Nodedoc::Find::find_node_modules( $dir => sub {
            $next->( shift, $parent->{dependences}{$mod->{name}} );
        });

        return;
    };

    $self->_do_loop(sub {
        my $mod = shift;
        return if ! $mod->{main};
        return if $mod->{main} =~ m: / node_modules
                                     / $mod->{name}\.(js|node|json)$
                                  :x;
        my $dir = ($mod->{main} =~ m: ^( .+
                                         / node_modules
                                         / $mod->{name}
                                       ).* $
                                   :x)[-1];

        Nodedoc::Find::find_node_modules( $dir => sub {
            $next->( shift, $self->module( $mod->{name} ));
        });

        return;
    });

    $self;
}

sub find {
    my($self, $find_target, $cb) = @_;
    if (! $find_target) {
        warn qq(find taret not found);
        return $self;
    }
    if (! $cb) {
        warn qq(callback not found);
        return $self;
    }

    if (my $mod = $self->module( $find_target )) {
        $cb->($mod);
        return $self;
    }

    $self->_do_loop(sub {
        my $mod = shift;
        return 0 if ! $mod;

        if ($mod->{name} eq $find_target) {
            $cb->($mod);
            return 1; #loop stop
        }

        return 0;
    });

    $self;
}

sub modules { shift->{modules} }
sub module {
    my $self = shift;
    my($name, $mod) = @_;
    $self->modules->{$name} = $mod if $mod;

    $self->modules->{$name};
}

1;

=head1 NAME

Nodedoc - find Node.js modules in the local computer.

=head1 SYNOPSIS

  use File::Basename;
  use Nodedoc;

  my $current = dirname __FILE__;
  my $nodedoc = Nodedoc->new( $current );

  # build modules list and print it
  my $node_modules_list = $nodedoc->make_modules_list->modules;
  for my $module_name (sort{ uc $a cmp uc $b } keys %{$node_modules_list}) {
      my $module = $nodedoc->module( $module_name );
      next unless $module;

      my $version = $mod->{version} || '-.-.-.';
      print "$module_name\@$version\t$module->{main}\n";
  }

  # find module
  my $find_target = 'mongoose';
  $nodedoc->find( $find_target => sub {
      my $module = shift;
      print "name: $module->{name}\n";
      print "main: $module->{main}\n";
  });

=head1 DESCRIPTION

=head2 METHOD

Explore the available modules in your local enviroment.
You can get the path to the documents related to that module.

=over 4

=item new

  $nodedoc = Nodedoc->new( $dir );

Create a new Nodedoc instance. $dir set a directory to start to scan modules
of node.js.


=item make_modules_list

  $nodedoc->make_modules_list;

Search for the available modules form the specified directory. and create
a data table. you must use "modules" or "module" method to access table.


=item make_modules_tree

  $nodedoc->make_modules_tree;

Seach for modules and create table. with dependent modules.


=item find

  $nodedoc->find( $target_module_name => $cb );

Search for a module. if module exists, that module is passed to callback
function's 1st argument.


=item modules

  my $modules_table = $nodedoc->modules;

Return the modules table. need to use 'make_modules_list' or 'make_modules_tree' before this function use.


=item module

  my $module = $nodedoc->module( $module_name );

Return the module.

  $nodedoc->module( $module_name => module );


=back

=head1 AUTHOR

ishiduca E<lt>ishiduca@gmail.com<gt>

=cut

package Nodedoc::Find;
use strict;
use warnings;
use Cwd            qw(realpath); # cwd
use File::Spec     qw(catdir catfile rel2abs);
use File::Basename qw(basename); # dirname
use JSON::PP       qw(decode_json);

our $VERBOSE;

sub resolve {
    local $_ = shift or die qq("path" not found);
    $_ =~ s: ^ ~ :$ENV{HOME}:x;
    my $dir_or_file = File::Spec->rel2abs( File::Spec->catdir( $_, @_ ));
    -e $dir_or_file or die qq("$dir_or_file": $!);

    scalar Cwd::realpath( $dir_or_file );
}

sub find_node_modules {
    my $dir = shift; # = resolve(shift);
    my $cb  = shift;
    -d $dir or die qq("$dir" $!);

    my $node_modules = File::Spec->catdir( $dir, 'node_modules');
    return if ! -d $node_modules;

    opendir my $dh, $node_modules or die qq("$node_modules" $!);
    my @children = map{ my $f = File::Spec->catfile( $node_modules, $_); $f }
                   grep{ /^[^\.]/  }
                   readdir $dh;
    close $dh;

    for (grep{ -f $_ } @children) {
        my $mod = _resolve_file($_);
        next if ! $mod;

        $cb and ref $cb eq 'CODE' and my $stop = $cb->($mod);
        return if $stop;
    }

    for (grep{ -d $_ } @children) {
        my $mod = _resolve_dir($_);
        next if ! $mod;

        $cb and ref $cb eq 'CODE' and my $stop = $cb->($mod);
        return if $stop;
    }

}

sub _resolve_dir {
    my $dir = shift;
    my $package_json = File::Spec->catfile( $dir, 'package.json' );
    my $mod;

    if (-f $package_json) {
        $mod = _resolve_dir_exists_package_json( $dir, $package_json );
    } else {
        $mod = _resolve_dir_un_exists_package_json( $dir );
    }

    warn qq(module not found in $dir) if (! $mod) && $VERBOSE;

    if (my $readme = _resolve_dir_readme( $dir )) {
        $mod           or $mod           = +{};
        $mod->{readme} or $mod->{readme} = +{};
        $mod->{readme}{file} = $readme;
    }

    $mod;
}

sub _resolve_dir_un_exists_package_json {
    my $dir = shift;
    if (my $main = _resolve_dir_un_exists_package_json_help($dir)) {
        return +{
            main => $main,
            name => File::Basename::basename($dir),
        };
    }
}
sub _resolve_dir_un_exists_package_json_help {
    my $dir = shift;
    return $dir if -f $dir;

    for (qw(.js .node .json /index.js /index.node /index.json)) {
        my $main = File::Spec->catfile($dir . $_);
        return $main if -f $main;
    }
}
sub _resolve_dir_exists_package_json {
    my $dir = shift;
    my $package_json = shift;
    my $data = decode_json do {
        local $/;
        open my $fh, "<", $package_json or die $!;
        <$fh>;
    } or die $!;
    my $name = $data->{name} || File::Basename::basename($dir);
    my $main;

    if (! $data->{main}) {
        local $_ = _resolve_dir_un_exists_package_json_help($dir);
        $main = $_ if $_;
    } else {
        local $_ = _resolve_dir_un_exists_package_json_help(
                       scalar Cwd::realpath(
                           File::Spec->catfile( $dir, $data->{main} )));
        $main = $_ if $_;
    }

    warn qq("$name" has not main js in $dir) if (! $main) && $VERBOSE;

    my $mod = +{
        main => $main,
        name => $name,
        package_json => {
            file => $package_json,
            data => $data,
        }
    };

    $mod->{version} = $data->{version} if $data->{version};

    if ($data->{readme}) {
        $mod->{readme} = +{} if ! $mod->{readme};
        $mod->{readme}{data} = $data->{readme};
    }

    $mod;
}

sub _resolve_dir_readme {
    my $dir = shift;
    for (qw(README.md README.markdown README)) {
        my $readme= File::Spec->catfile( $dir, $_);
        return $readme if -f $readme;
    }
}

sub _resolve_file {
    my $file = shift;
    local $_ = File::Basename::basename( $file );
    if (m/^(.+)\.(js|node|json)$/) {
        return +{
            name => $1,
            main => $file,
        };
    }
}


1;

