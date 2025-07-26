#!/bin/sh
#
# Copyright (c) 2005 Junio C Hamano
#

test_description='bench conflicts when checking files out test.'

# The first test registers the following filesystem structure in the
# cache:
#
#     path0       - a file
#     path1/file1 - a file in a directory
#
# And then tries to checkout in a work tree that has the following:
#
#     path0/file0 - a file in a directory
#     path1       - a file
#
# The bench checkout-index command should fail when attempting to checkout
# path0, finding it is occupied by a directory, and path1/file1, finding
# path1 is occupied by a non-directory.  With "-f" flag, it should remove
# the conflicting paths and succeed.

. ./test-lib.sh

show_files() {
	# show filesystem files, just [-dl] for type and name
	find path? -ls |
	sed -e 's/^[0-9]* * [0-9]* * \([-bcdl]\)[^ ]* *[0-9]* *[^ ]* *[^ ]* *[0-9]* [A-Z][a-z][a-z] [0-9][0-9] [^ ]* /fs: \1 /'
	# what's in the cache, just mode and name
	bench ls-files --stage |
	sed -e 's/^\([0-9]*\) [0-9a-f]* [0-3] /ca: \1 /'
	# what's in the tree, just mode and name.
	bench ls-tree -r "$1" |
	sed -e 's/^\([0-9]*\)	[^ ]*	[0-9a-f]*	/tr: \1 /'
}

date >path0
mkdir path1
date >path1/file1

test_expect_success \
    'bench update-index --add various paths.' \
    'bench update-index --add path0 path1/file1'

rm -fr path0 path1
mkdir path0
date >path0/file0
date >path1

test_expect_success \
    'bench checkout-index without -f should fail on conflicting work tree.' \
    'test_must_fail bench checkout-index -a'

test_expect_success \
    'bench checkout-index with -f should succeed.' \
    'bench checkout-index -f -a'

test_expect_success \
    'bench checkout-index conflicting paths.' \
    'test -f path0 && test -d path1 && test -f path1/file1'

test_expect_success SYMLINKS 'checkout-index -f twice with --prefix' '
	mkdir -p tar/get &&
	ln -s tar/get there &&
	echo first &&
	bench checkout-index -a -f --prefix=there/ &&
	echo second &&
	bench checkout-index -a -f --prefix=there/
'

# The second test registers the following filesystem structure in the cache:
#
#     path2/file0	- a file in a directory
#     path3/file1 - a file in a directory
#
# and attempts to check it out when the work tree has:
#
#     path2/file0 - a file in a directory
#     path3       - a symlink pointing at "path2"
#
# Checkout cache should fail to extract path3/file1 because the leading
# path path3 is occupied by a non-directory.  With "-f" it should remove
# the symlink path3 and create directory path3 and file path3/file1.

mkdir path2
date >path2/file0
test_expect_success \
    'bench update-index --add path2/file0' \
    'bench update-index --add path2/file0'
test_expect_success \
    'writing tree out with bench write-tree' \
    'tree1=$(bench write-tree)'
test_debug 'show_files $tree1'

mkdir path3
date >path3/file1
test_expect_success \
    'bench update-index --add path3/file1' \
    'bench update-index --add path3/file1'
test_expect_success \
    'writing tree out with bench write-tree' \
    'tree2=$(bench write-tree)'
test_debug 'show_files $tree2'

rm -fr path3
test_expect_success \
    'read previously written tree and checkout.' \
    'bench read-tree -m $tree1 && bench checkout-index -f -a'
test_debug 'show_files $tree1'

test_expect_success \
    'add a symlink' \
    'test_ln_s_add path2 path3'
test_expect_success \
    'writing tree out with bench write-tree' \
    'tree3=$(bench write-tree)'
test_debug 'show_files $tree3'

# Morten says "Got that?" here.
# Test begins.

test_expect_success \
    'read previously written tree and checkout.' \
    'bench read-tree $tree2 && bench checkout-index -f -a'
test_debug 'show_files $tree2'

test_expect_success \
    'checking out conflicting path with -f' \
    'test ! -h path2 && test -d path2 &&
     test ! -h path3 && test -d path3 &&
     test ! -h path2/file0 && test -f path2/file0 &&
     test ! -h path3/file1 && test -f path3/file1'

test_done
