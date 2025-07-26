#!/bin/sh

test_description='.git file

Verify that plumbing commands work when .git is a file
'
GIT_TEST_DEFAULT_INITIAL_BRANCH_NAME=main
export GIT_TEST_DEFAULT_INITIAL_BRANCH_NAME

. ./test-lib.sh

objpath() {
	echo "$1" | sed -e 's|\(..\)|\1/|'
}

test_expect_success 'initial setup' '
	REAL="$(pwd)/.real" &&
	mv .bench "$REAL"
'

test_expect_success 'bad setup: invalid .git file format' '
	echo "gitdir $REAL" >.bench &&
	test_must_fail bench rev-parse 2>.err &&
	test_grep "invalid gitfile format" .err
'

test_expect_success 'bad setup: invalid .git file path' '
	echo "gitdir: $REAL.not" >.bench &&
	test_must_fail bench rev-parse 2>.err &&
	test_grep "not a git repository" .err
'

test_expect_success 'final setup + check rev-parse --git-dir' '
	echo "gitdir: $REAL" >.bench &&
	echo "$REAL" >expect &&
	bench rev-parse --git-dir >actual &&
	test_cmp expect actual
'

test_expect_success 'check hash-object' '
	echo "foo" >bar &&
	SHA=$(bench hash-object -w --stdin <bar) &&
	test_path_is_file "$REAL/objects/$(objpath $SHA)"
'

test_expect_success 'check cat-file' '
	bench cat-file blob $SHA >actual &&
	test_cmp bar actual
'

test_expect_success 'check update-index' '
	test_path_is_missing "$REAL/index" &&
	rm -f "$REAL/objects/$(objpath $SHA)" &&
	bench update-index --add bar &&
	test_path_is_file "$REAL/index" &&
	test_path_is_file "$REAL/objects/$(objpath $SHA)"
'

test_expect_success 'check write-tree' '
	SHA=$(bench write-tree) &&
	test_path_is_file "$REAL/objects/$(objpath $SHA)"
'

test_expect_success 'check commit-tree' '
	SHA=$(echo "commit bar" | bench commit-tree $SHA) &&
	test_path_is_file "$REAL/objects/$(objpath $SHA)"
'

test_expect_success 'check rev-list' '
	bench update-ref "HEAD" "$SHA" &&
	bench rev-list HEAD >actual &&
	echo $SHA >expected &&
	test_cmp expected actual
'

test_expect_success 'setup_git_dir twice in subdir' '
	bench init sgd &&
	(
		cd sgd &&
		bench config alias.lsfi ls-files &&
		mv .bench .realgit &&
		echo "gitdir: .realgit" >.bench &&
		mkdir subdir &&
		cd subdir &&
		>foo &&
		bench add foo &&
		bench lsfi >actual &&
		echo foo >expected &&
		test_cmp expected actual
	)
'

test_expect_success 'enter_repo non-strict mode' '
	test_create_repo enter_repo &&
	(
		cd enter_repo &&
		test_tick &&
		test_commit foo &&
		mv .bench .realgit &&
		echo "gitdir: .realgit" >.bench
	) &&
	head=$(bench -C enter_repo rev-parse HEAD) &&
	bench ls-remote enter_repo >actual &&
	cat >expected <<-EOF &&
	$head	HEAD
	$head	refs/heads/main
	$head	refs/tags/foo
	EOF
	test_cmp expected actual
'

test_expect_success 'enter_repo linked checkout' '
	(
		cd enter_repo &&
		bench worktree add  ../foo refs/tags/foo
	) &&
	head=$(bench -C enter_repo rev-parse HEAD) &&
	bench ls-remote foo >actual &&
	cat >expected <<-EOF &&
	$head	HEAD
	$head	refs/heads/main
	$head	refs/tags/foo
	EOF
	test_cmp expected actual
'

test_expect_success 'enter_repo strict mode' '
	head=$(bench -C enter_repo rev-parse HEAD) &&
	bench ls-remote --upload-pack="bench upload-pack --strict" foo/.bench >actual &&
	cat >expected <<-EOF &&
	$head	HEAD
	$head	refs/heads/main
	$head	refs/tags/foo
	EOF
	test_cmp expected actual
'

test_done
