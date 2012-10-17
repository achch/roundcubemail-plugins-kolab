#!/usr/bin/env php -d enable_dl=On
<?php

/**
 * Kolab storage cache modification script
 *
 * @version 3.0
 * @author Thomas Bruederli <bruederli@kolabsys.com>
 *
 * Copyright (C) 2012, Kolab Systems AG <contact@kolabsys.com>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

define('INSTALL_PATH', realpath('.') . '/' );
ini_set('display_errors', 1);

if (!file_exists(INSTALL_PATH . 'program/include/clisetup.php'))
    die("Execute this from the Roundcube installation dir!\n\n");

require_once INSTALL_PATH . 'program/include/clisetup.php';

function print_usage()
{
	print "Usage:  modcache.sh [OPTIONS] ACTION [USERNAME ARGS ...]\n";
	print "Possible actions are: expunge, clear, prewarm\n";
	print "-a, --all      Clear/expunge all caches\n";
	print "-h, --host     IMAP host name\n";
	print "-u, --user     IMAP user name to authenticate\n";
	print "-t, --type     Object types to clear/expunge cache\n";
	print "-l, --limit    Limit the number of records to be expunged\n";
}

// read arguments
$opts = get_opt(array(
    'a' => 'all',
    'h' => 'host',
    'u' => 'user',
    'p' => 'password',
    't' => 'type',
    'l' => 'limit',
    'v' => 'verbose',
));

$opts['username'] = !empty($opts[1]) ? $opts[1] : $opts['user'];
$action = $opts[0];

$rcmail = rcube::get_instance();


/*
 * Script controller
 */
switch (strtolower($action)) {

/*
 * Clear/expunge all cache records
 */
case 'expunge':
    $expire = strtotime(!empty($opts[2]) ? $opts[2] : 'now - 10 days');
    $sql_add = " AND created <= '" . date('Y-m-d 00:00:00', $expire) . "'";
    if ($opts['limit']) {
        $sql_add .= ' LIMIT ' . intval($opts['limit']);
    }

case 'clear':
    // connect to database
    $db = $rcmail->get_dbh();
    $db->db_connect('w');
    if (!$db->is_connected() || $db->is_error())
        die("No DB connection\n");

    $folder_types = $opts['type'] ? explode(',', $opts['type']) : array('contact','distribution-list','event','task','configuration');
    $folder_types_db = array_map(array($db, 'quote'), $folder_types);

    if ($opts['all']) {
        $sql_query = "DELETE FROM kolab_cache WHERE type IN (" . join(',', $folder_types_db) . ")";
    }
    else if ($opts['username']) {
        $sql_query = "DELETE FROM kolab_cache WHERE type IN (" . join(',', $folder_types_db) . ") AND resource LIKE ?";
    }

    if ($sql_query) {
        $db->query($sql_query . $sql_add, resource_prefix($opts).'%');
        echo $db->affected_rows() . " records deleted from 'kolab_cache'\n";
    }
    break;


/*
 * Prewarm cache by synchronizing objects for the given user
 */
case 'prewarm':
    // make sure libkolab classes are loaded
    $rcmail->plugins->load_plugin('libkolab');

    if (authenticate($opts)) {
        $folder_types = $opts['type'] ? explode(',', $opts['type']) : array('contact','event','task','configuration');
        foreach ($folder_types as $type) {
            // sync every folder of the given type
            foreach (kolab_storage::get_folders($type) as $folder) {
                echo "Synching " . $folder->name . " ($type) ... ";
                echo $folder->count($type) . "\n";

                // also sync distribution lists in contact folders
                if ($type == 'contact') {
                    echo "Synching " . $folder->name . " (distribution-list) ... ";
                    echo $folder->count('distribution-list') . "\n";
                }
            }
        }
    }
    else
        die("Authentication failed for " . $opts['user']);
    break;


/*
 * Unknown action => show usage
 */
default:
    print_usage();
    exit;
}


/**
 * Compose cache resource URI prefix for the given user credentials
 */
function resource_prefix($opts)
{
    return 'imap://' . urlencode($opts['username']) . '@' . $opts['host'] . '/';
}


/**
 * Authenticate to the IMAP server with the given user credentials
 */
function authenticate(&$opts)
{
    global $rcmail;

    // prompt for password
    if (empty($opts['password']) && ($opts['username'] || $opts['user'])) {
        $opts['password'] = prompt_silent("Password: ");
    }

    // simulate "login as" feature
    if ($opts['user'] && $opts['user'] != $opts['username'])
        $_POST['_loginas'] = $opts['username'];
    else if (empty($opts['user']))
        $opts['user'] = $opts['username'];

    // let the kolab_auth plugin do its magic
    $auth = $rcmail->plugins->exec_hook('authenticate', array(
        'host' => trim($opts['host']),
        'user' => trim($opts['user']),
        'pass' => $opts['password'],
        'cookiecheck' => false,
        'valid' => !empty($opts['user']) && !empty($opts['host']),
    ));

    if ($auth['valid']) {
        $storage = $rcmail->get_storage();
        if ($storage->connect($auth['host'], $auth['user'], $auth['pass'], 143, false)) {
            if ($opts['verbose'])
                echo "IMAP login succeeded.\n";
            if (($user = rcube_user::query($opts['username'], $auth['host'])) && $user->ID)
                $rcmail->set_user($user);
        }
        else
            die("Login to IMAP server failed!\n");
    }
    else {
        die("Invalid login credentials!\n");
    }

    return $auth['valid'];
}

