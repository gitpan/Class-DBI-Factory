#!/usr/bin/perl

use strict;
use warnings;

use lib '[% demo_root %]/lib';
use POSIX ();
use Apache ();
use Apache::Request ();
use Apache::Cookie ();
use Apache::Constants qw(:response);
use Apache::Util ();
use Apache::Status ();
use DBI; 
DBI->install_driver('SQLite');
use Template ();
use Class::DBI ();
use Class::DBI::Factory ();
Class::DBI::Factory->add_status_menu;

1;
