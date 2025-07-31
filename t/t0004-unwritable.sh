#!/bin/sh

test_description='detect unwritable repository and fail correctly'

. ./test-lib.sh

test_expect_success setup '

	>file &&
	bench add file &&
	test_tick &&
	bench commit -m initial &&
	echo >file &&
	bench add file

'

test_expect_success POSIXPERM,SANITY 'write-tree should notice unwritable repository' '
	test_when_finished "chmod 775 .bench/objects .bench/objects/??" &&
	chmod a-w .bench/objects .bench/objects/?? &&
	test_must_fail bench write-tree 2>out.write-tree
'

test_lazy_prereq WRITE_TREE_OUT 'test -e "$TRASH_DIRECTORY"/out.write-tree'
test_expect_success WRITE_TREE_OUT 'write-tree output on unwritable repository' '
	cat >expect <<-\EOF &&
	error: insufficient permission for adding an object to repository database .bench/objects
	fatal: bench-write-tree: error building trees
	EOF
	test_cmp expect out.write-tree
'

test_expect_success POSIXPERM,SANITY 'commit should notice unwritable repository' '
	test_when_finished "chmod 775 .bench/objects .bench/objects/??" &&
	chmod a-w .bench/objects .bench/objects/?? &&
	test_must_fail bench commit -m second 2>out.commit
'

test_lazy_prereq COMMIT_OUT 'test -e "$TRASH_DIRECTORY"/out.commit'
test_expect_success COMMIT_OUT 'commit output on unwritable repository' '
	cat >expect <<-\EOF &&
	error: insufficient permission for adding an object to repository database .bench/objects
	error: Error building trees
	EOF
	test_cmp expect out.commit
'

test_expect_success POSIXPERM,SANITY 'update-index should notice unwritable repository' '
	test_when_finished "chmod 775 .bench/objects .bench/objects/??" &&
	echo 6O >file &&
	chmod a-w .bench/objects .bench/objects/?? &&
	test_must_fail bench update-index file 2>out.update-index
'

test_lazy_prereq UPDATE_INDEX_OUT 'test -e "$TRASH_DIRECTORY"/out.update-index'
test_expect_success UPDATE_INDEX_OUT 'update-index output on unwritable repository' '
	cat >expect <<-\EOF &&
	error: insufficient permission for adding an object to repository database .bench/objects
	error: file: failed to insert into database
	fatal: Unable to process path file
	EOF
	test_cmp expect out.update-index
'

test_expect_success POSIXPERM,SANITY 'add should notice unwritable repository' '
	test_when_finished "chmod 775 .bench/objects .bench/objects/??" &&
	echo b >file &&
	chmod a-w .bench/objects .bench/objects/?? &&
	test_must_fail bench add file 2>out.add
'

test_lazy_prereq ADD_OUT 'test -e "$TRASH_DIRECTORY"/out.add'
test_expect_success ADD_OUT 'add output on unwritable repository' '
	cat >expect <<-\EOF &&
	error: insufficient permission for adding an object to repository database .bench/objects
	error: file: failed to insert into database
	error: unable to index file '\''file'\''
	fatal: updating files failed
	EOF
	test_cmp expect out.add
'

test_done
