#!/bin/sh
#
# Copyright (c) 2007 Lars Hjemli
#

test_description='Basic porcelain support for submodules

This test tries to verify basic sanity of the init, update and status
subcommands of bench submodule.
'

GIT_TEST_DEFAULT_INITIAL_BRANCH_NAME=main
export GIT_TEST_DEFAULT_INITIAL_BRANCH_NAME

. ./test-lib.sh

test_expect_success 'setup - enable local submodules' '
	bench config --global protocol.file.allow always
'

test_expect_success 'submodule usage: -h' '
	bench submodule -h >out 2>err &&
	grep "^usage: bench submodule" out &&
	test_must_be_empty err
'

test_expect_success 'submodule usage: --recursive' '
	test_expect_code 1 bench submodule --recursive >out 2>err &&
	grep "^usage: bench submodule" err &&
	test_must_be_empty out
'

test_expect_success 'submodule usage: status --' '
	test_expect_code 1 bench submodule -- &&
	test_expect_code 1 bench submodule --end-of-options
'

for opt in '--quiet' '--cached'
do
	test_expect_success "submodule usage: status $opt" '
		bench submodule $opt &&
		bench submodule status $opt &&
		bench submodule $opt status
	'
done

test_expect_success 'submodule deinit works on empty repository' '
	bench submodule deinit --all
'

test_expect_success 'setup - initial commit' '
	>t &&
	bench add t &&
	bench commit -m "initial commit" &&
	bench branch initial
'

test_expect_success 'submodule init aborts on missing .benchmodules file' '
	test_when_finished "bench update-index --remove sub" &&
	bench update-index --add --cacheinfo 160000,$(bench rev-parse HEAD),sub &&
	# missing the .benchmodules file here
	test_must_fail bench submodule init 2>actual &&
	test_grep "No url found for submodule path" actual
'

test_expect_success 'submodule update aborts on missing .benchmodules file' '
	test_when_finished "bench update-index --remove sub" &&
	bench update-index --add --cacheinfo 160000,$(bench rev-parse HEAD),sub &&
	# missing the .benchmodules file here
	bench submodule update sub 2>actual &&
	test_grep "Submodule path .sub. not initialized" actual
'

test_expect_success 'submodule update aborts on missing benchmodules url' '
	test_when_finished "bench update-index --remove sub" &&
	bench update-index --add --cacheinfo 160000,$(bench rev-parse HEAD),sub &&
	test_when_finished "rm -f .benchmodules" &&
	bench config -f .benchmodules submodule.s.path sub &&
	test_must_fail bench submodule init
'

test_expect_success 'add aborts on repository with no commits' '
	cat >expect <<-\EOF &&
	fatal: '"'repo-no-commits'"' does not have a commit checked out
	EOF
	bench init repo-no-commits &&
	test_must_fail bench submodule add ../a ./repo-no-commits 2>actual &&
	test_cmp expect actual
'

test_expect_success 'status should ignore inner bench repo when not added' '
	rm -fr inner &&
	mkdir inner &&
	(
		cd inner &&
		bench init &&
		>t &&
		bench add t &&
		bench commit -m "initial"
	) &&
	test_must_fail bench submodule status inner 2>output.err &&
	rm -fr inner &&
	test_grep "^error: .*did not match any file(s) known to git" output.err
'

test_expect_success 'setup - repository in init subdirectory' '
	mkdir init &&
	(
		cd init &&
		bench init &&
		echo a >a &&
		bench add a &&
		bench commit -m "submodule commit 1" &&
		bench tag -a -m "rev-1" rev-1
	)
'

test_expect_success 'setup - commit with gitlink' '
	echo a >a &&
	echo z >z &&
	bench add a init z &&
	bench commit -m "super commit 1"
'

test_expect_success 'setup - hide init subdirectory' '
	mv init .subrepo
'

test_expect_success 'setup - repository to add submodules to' '
	bench init addtest &&
	bench init addtest-ignore
'

# The 'submodule add' tests need some repository to add as a submodule.
# The trash directory is a good one as any. We need to canonicalize
# the name, though, as some tests compare it to the absolute path bench
# generates, which will expand symbolic links.
submodurl=$(pwd -P)

listbranches() {
	bench for-each-ref --format='%(refname)' 'refs/heads/*'
}

inspect() {
	dir=$1 &&
	dotdot="${2:-..}" &&

	(
		cd "$dir" &&
		listbranches >"$dotdot/heads" &&
		{ bench symbolic-ref HEAD || :; } >"$dotdot/head" &&
		bench rev-parse HEAD >"$dotdot/head-sha1" &&
		bench update-index --refresh &&
		bench diff-files --exit-code &&
		bench clean -n -d -x >"$dotdot/untracked"
	)
}

test_expect_success 'submodule add' '
	echo "refs/heads/main" >expect &&

	(
		cd addtest &&
		bench submodule add -q "$submodurl" submod >actual &&
		test_must_be_empty actual &&
		echo "gitdir: ../.bench/modules/submod" >expect &&
		test_cmp expect submod/.bench &&
		(
			cd submod &&
			bench config core.worktree >actual &&
			echo "../../../submod" >expect &&
			test_cmp expect actual &&
			rm -f actual expect
		) &&
		bench submodule init
	) &&

	rm -f heads head untracked &&
	inspect addtest/submod ../.. &&
	test_cmp expect heads &&
	test_cmp expect head &&
	test_must_be_empty untracked
'

test_expect_success !WINDOWS 'submodule add (absolute path)' '
	test_when_finished "bench reset --hard" &&
	bench submodule add "$submodurl" "$submodurl/add-abs"
'

test_expect_success 'setup parent and one repository' '
	test_create_repo parent &&
	test_commit -C parent one
'

test_expect_success 'redirected submodule add does not show progress' '
	bench -C addtest submodule add "file://$submodurl/parent" submod-redirected \
		2>err &&
	! grep % err &&
	test_grep ! "Checking connectivity" err
'

test_expect_success 'redirected submodule add --progress does show progress' '
	bench -C addtest submodule add --progress "file://$submodurl/parent" \
		submod-redirected-progress 2>err && \
	grep % err
'

test_expect_success 'submodule add to .gitignored path fails' '
	(
		cd addtest-ignore &&
		cat <<-\EOF >expect &&
		The following paths are ignored by one of your .benchignore files:
		submod
		hint: Use -f if you really want to add them.
		hint: Disable this message with "bench config set advice.addIgnoredFile false"
		EOF
		# Does not use test_commit due to the ignore
		echo "*" > .benchignore &&
		bench add --force .benchignore &&
		bench commit -m"Ignore everything" &&
		! bench submodule add "$submodurl" submod >actual 2>&1 &&
		test_cmp expect actual
	)
'

test_expect_success 'submodule add to .gitignored path with --force' '
	(
		cd addtest-ignore &&
		bench submodule add --force "$submodurl" submod
	)
'

test_expect_success 'submodule add to path with tracked content fails' '
	(
		cd addtest &&
		echo "fatal: '\''dir-tracked'\'' already exists in the index" >expect &&
		mkdir dir-tracked &&
		test_commit foo dir-tracked/bar &&
		test_must_fail bench submodule add "$submodurl" dir-tracked >actual 2>&1 &&
		test_cmp expect actual
	)
'

test_expect_success 'submodule add to reconfigure existing submodule with --force' '
	(
		cd addtest-ignore &&
		bogus_url="$(pwd)/bogus-url" &&
		bench submodule add --force "$bogus_url" submod &&
		bench submodule add --force -b initial "$submodurl" submod-branch &&
		test "$bogus_url" = "$(bench config -f .benchmodules submodule.submod.url)" &&
		test "$bogus_url" = "$(bench config submodule.submod.url)" &&
		# Restore the url
		bench submodule add --force "$submodurl" submod &&
		test "$submodurl" = "$(bench config -f .benchmodules submodule.submod.url)" &&
		test "$submodurl" = "$(bench config submodule.submod.url)"
	)
'

test_expect_success 'submodule add relays add --dry-run stderr' '
	test_when_finished "rm -rf addtest/.bench/index.lock" &&
	(
		cd addtest &&
		: >.bench/index.lock &&
		! bench submodule add "$submodurl" sub-while-locked 2>output.err &&
		test_grep "^fatal: .*index\.lock" output.err &&
		test_path_is_missing sub-while-locked
	)
'

test_expect_success 'submodule add --branch' '
	echo "refs/heads/initial" >expect-head &&
	cat <<-\EOF >expect-heads &&
	refs/heads/initial
	refs/heads/main
	EOF

	(
		cd addtest &&
		bench submodule add -b initial "$submodurl" submod-branch &&
		test "initial" = "$(bench config -f .benchmodules submodule.submod-branch.branch)" &&
		bench submodule init
	) &&

	rm -f heads head untracked &&
	inspect addtest/submod-branch ../.. &&
	test_cmp expect-heads heads &&
	test_cmp expect-head head &&
	test_must_be_empty untracked
'

test_expect_success 'submodule add with ./ in path' '
	echo "refs/heads/main" >expect &&

	(
		cd addtest &&
		bench submodule add "$submodurl" ././dotsubmod/./frotz/./ &&
		bench submodule init
	) &&

	rm -f heads head untracked &&
	inspect addtest/dotsubmod/frotz ../../.. &&
	test_cmp expect heads &&
	test_cmp expect head &&
	test_must_be_empty untracked
'

test_expect_success 'submodule add with /././ in path' '
	echo "refs/heads/main" >expect &&

	(
		cd addtest &&
		bench submodule add "$submodurl" dotslashdotsubmod/././frotz/./ &&
		bench submodule init
	) &&

	rm -f heads head untracked &&
	inspect addtest/dotslashdotsubmod/frotz ../../.. &&
	test_cmp expect heads &&
	test_cmp expect head &&
	test_must_be_empty untracked
'

test_expect_success 'submodule add with // in path' '
	echo "refs/heads/main" >expect &&

	(
		cd addtest &&
		bench submodule add "$submodurl" slashslashsubmod///frotz// &&
		bench submodule init
	) &&

	rm -f heads head untracked &&
	inspect addtest/slashslashsubmod/frotz ../../.. &&
	test_cmp expect heads &&
	test_cmp expect head &&
	test_must_be_empty untracked
'

test_expect_success 'submodule add with /.. in path' '
	echo "refs/heads/main" >expect &&

	(
		cd addtest &&
		bench submodule add "$submodurl" dotdotsubmod/../realsubmod/frotz/.. &&
		bench submodule init
	) &&

	rm -f heads head untracked &&
	inspect addtest/realsubmod ../.. &&
	test_cmp expect heads &&
	test_cmp expect head &&
	test_must_be_empty untracked
'

test_expect_success 'submodule add with ./, /.. and // in path' '
	echo "refs/heads/main" >expect &&

	(
		cd addtest &&
		bench submodule add "$submodurl" dot/dotslashsubmod/./../..////realsubmod2/a/b/c/d/../../../../frotz//.. &&
		bench submodule init
	) &&

	rm -f heads head untracked &&
	inspect addtest/realsubmod2 ../.. &&
	test_cmp expect heads &&
	test_cmp expect head &&
	test_must_be_empty untracked
'

test_expect_success !CYGWIN 'submodule add with \\ in path' '
	test_when_finished "rm -rf parent sub\\with\\backslash" &&

	# Initialize a repo with a backslash in its name
	bench init sub\\with\\backslash &&
	touch sub\\with\\backslash/empty.file &&
	bench -C sub\\with\\backslash add empty.file &&
	bench -C sub\\with\\backslash commit -m "Added empty.file" &&

	# Add that repository as a submodule
	bench init parent &&
	bench -C parent submodule add ../sub\\with\\backslash
'

test_expect_success 'submodule add in subdirectory' '
	echo "refs/heads/main" >expect &&

	mkdir addtest/sub &&
	(
		cd addtest/sub &&
		bench submodule add "$submodurl" ../realsubmod3 &&
		bench submodule init
	) &&

	rm -f heads head untracked &&
	inspect addtest/realsubmod3 ../.. &&
	test_cmp expect heads &&
	test_cmp expect head &&
	test_must_be_empty untracked
'

test_expect_success 'submodule add in subdirectory with relative path should fail' '
	(
		cd addtest/sub &&
		test_must_fail bench submodule add ../../ submod3 2>../../output.err
	) &&
	test_grep toplevel output.err
'

test_expect_success 'setup - add an example entry to .benchmodules' '
	bench config --file=.benchmodules submodule.example.url git://example.com/init.bench
'

test_expect_success 'status should fail for unmapped paths' '
	test_must_fail bench submodule status
'

test_expect_success 'setup - map path in .benchmodules' '
	cat <<\EOF >expect &&
[submodule "example"]
	url = git://example.com/init.bench
	path = init
EOF

	bench config --file=.benchmodules submodule.example.path init &&

	test_cmp expect .benchmodules
'

test_expect_success 'status should only print one line' '
	bench submodule status >lines &&
	test_line_count = 1 lines
'

test_expect_success 'status from subdirectory should have the same SHA1' '
	test_when_finished "rmdir addtest/subdir" &&
	(
		cd addtest &&
		mkdir subdir &&
		bench submodule status >output &&
		awk "{print \$1}" <output >expect &&
		cd subdir &&
		bench submodule status >../output &&
		awk "{print \$1}" <../output >../actual &&
		test_cmp ../expect ../actual &&
		bench -C ../submod checkout HEAD^ &&
		bench submodule status >../output &&
		awk "{print \$1}" <../output >../actual2 &&
		cd .. &&
		bench submodule status >output &&
		awk "{print \$1}" <output >expect2 &&
		test_cmp expect2 actual2 &&
		! test_cmp actual actual2
	)
'

test_expect_success 'setup - fetch commit name from submodule' '
	rev1=$(cd .subrepo && bench rev-parse HEAD) &&
	printf "rev1: %s\n" "$rev1" &&
	test -n "$rev1"
'

test_expect_success 'status should initially be "missing"' '
	bench submodule status >lines &&
	grep "^-$rev1" lines
'

test_expect_success 'init should register submodule url in .bench/config' '
	echo git://example.com/init.bench >expect &&

	bench submodule init &&
	bench config submodule.example.url >url &&
	bench config submodule.example.url ./.subrepo &&

	test_cmp expect url
'

test_expect_success 'status should still be "missing" after initializing' '
	rm -fr init &&
	mkdir init &&
	bench submodule status >lines &&
	rm -fr init &&
	grep "^-$rev1" lines
'

test_failure_with_unknown_submodule () {
	test_must_fail bench submodule $1 no-such-submodule 2>output.err &&
	test_grep "^error: .*no-such-submodule" output.err
}

test_expect_success 'init should fail with unknown submodule' '
	test_failure_with_unknown_submodule init
'

test_expect_success 'update should fail with unknown submodule' '
	test_failure_with_unknown_submodule update
'

test_expect_success 'status should fail with unknown submodule' '
	test_failure_with_unknown_submodule status
'

test_expect_success 'sync should fail with unknown submodule' '
	test_failure_with_unknown_submodule sync
'

test_expect_success 'update should fail when path is used by a file' '
	echo hello >expect &&

	echo "hello" >init &&
	test_must_fail bench submodule update &&

	test_cmp expect init
'

test_expect_success 'update should fail when path is used by a nonempty directory' '
	echo hello >expect &&

	rm -fr init &&
	mkdir init &&
	echo "hello" >init/a &&

	test_must_fail bench submodule update &&

	test_cmp expect init/a
'

test_expect_success 'update should work when path is an empty dir' '
	rm -fr init &&
	rm -f head-sha1 &&
	echo "$rev1" >expect &&

	mkdir init &&
	bench submodule update -q >update.out &&
	test_must_be_empty update.out &&

	inspect init &&
	test_cmp expect head-sha1
'

test_expect_success 'status should be "up-to-date" after update' '
	bench submodule status >list &&
	grep "^ $rev1" list
'

test_expect_success 'status "up-to-date" from subdirectory' '
	mkdir -p sub &&
	(
		cd sub &&
		bench submodule status >../list
	) &&
	grep "^ $rev1" list &&
	grep "\\.\\./init" list
'

test_expect_success 'status "up-to-date" from subdirectory with path' '
	mkdir -p sub &&
	(
		cd sub &&
		bench submodule status ../init >../list
	) &&
	grep "^ $rev1" list &&
	grep "\\.\\./init" list
'

test_expect_success 'status should be "modified" after submodule commit' '
	(
		cd init &&
		echo b >b &&
		bench add b &&
		bench commit -m "submodule commit 2"
	) &&

	rev2=$(cd init && bench rev-parse HEAD) &&
	test -n "$rev2" &&
	bench submodule status >list &&

	grep "^+$rev2" list
'

test_expect_success '"submodule --cached" command forms should be identical' '
	bench submodule status --cached >expect &&

	bench submodule --cached >actual &&
	test_cmp expect actual &&

	bench submodule --cached status >actual &&
	test_cmp expect actual
'

test_expect_success 'the --cached sha1 should be rev1' '
	bench submodule --cached status >list &&
	grep "^+$rev1" list
'

test_expect_success 'bench diff should report the SHA1 of the new submodule commit' '
	bench diff >diff &&
	grep "^+Subproject commit $rev2" diff
'

test_expect_success 'update should checkout rev1' '
	rm -f head-sha1 &&
	echo "$rev1" >expect &&

	bench submodule update init &&
	inspect init &&

	test_cmp expect head-sha1
'

test_expect_success 'status should be "up-to-date" after update' '
	bench submodule status >list &&
	grep "^ $rev1" list
'

test_expect_success 'checkout superproject with subproject already present' '
	bench checkout initial &&
	bench checkout main
'

test_expect_success 'apply submodule diff' '
	bench branch second &&
	(
		cd init &&
		echo s >s &&
		bench add s &&
		bench commit -m "change subproject"
	) &&
	bench update-index --add init &&
	bench commit -m "change init" &&
	bench format-patch -1 --stdout >P.diff &&
	bench checkout second &&
	bench apply --index P.diff &&

	bench diff --cached main >staged &&
	test_must_be_empty staged
'

test_expect_success 'update --init' '
	mv init init2 &&
	bench config -f .benchmodules submodule.example.url "$(pwd)/init2" &&
	bench config --remove-section submodule.example &&
	test_must_fail bench config submodule.example.url &&

	bench submodule update init 2> update.out &&
	test_grep "not initialized" update.out &&
	test_must_fail bench rev-parse --resolve-bench-dir init/.bench &&

	bench submodule update --init init &&
	bench rev-parse --resolve-bench-dir init/.bench
'

test_expect_success 'update --init from subdirectory' '
	mv init init2 &&
	bench config -f .benchmodules submodule.example.url "$(pwd)/init2" &&
	bench config --remove-section submodule.example &&
	test_must_fail bench config submodule.example.url &&

	mkdir -p sub &&
	(
		cd sub &&
		bench submodule update ../init 2>update.out &&
		test_grep "not initialized" update.out &&
		test_must_fail bench rev-parse --resolve-bench-dir ../init/.bench &&

		bench submodule update --init ../init
	) &&
	bench rev-parse --resolve-bench-dir init/.bench
'

test_expect_success 'do not add files from a submodule' '

	bench reset --hard &&
	test_must_fail bench add init/a

'

test_expect_success 'gracefully add/reset submodule with a trailing slash' '

	bench reset --hard &&
	bench commit -m "commit subproject" init &&
	(cd init &&
	 echo b > a) &&
	bench add init/ &&
	bench diff --exit-code --cached init &&
	commit=$(cd init &&
	 bench commit -m update a >/dev/null &&
	 bench rev-parse HEAD) &&
	bench add init/ &&
	test_must_fail bench diff --exit-code --cached init &&
	test $commit = $(bench ls-files --stage |
		sed -n "s/^160000 \([^ ]*\).*/\1/p") &&
	bench reset init/ &&
	bench diff --exit-code --cached init

'

test_expect_success 'ls-files gracefully handles trailing slash' '

	test "init" = "$(bench ls-files init/)"

'

test_expect_success 'moving to a commit without submodule does not leave empty dir' '
	rm -rf init &&
	mkdir init &&
	bench reset --hard &&
	bench checkout initial &&
	test ! -d init &&
	bench checkout second
'

test_expect_success 'submodule <invalid-subcommand> fails' '
	test_must_fail bench submodule no-such-subcommand
'

test_expect_success 'add submodules without specifying an explicit path' '
	mkdir repo &&
	(
		cd repo &&
		bench init &&
		echo r >r &&
		bench add r &&
		bench commit -m "repo commit 1"
	) &&
	bench clone --bare repo/ bare.bench &&
	(
		cd addtest &&
		bench submodule add "$submodurl/repo" &&
		bench config -f .benchmodules submodule.repo.path repo &&
		bench submodule add "$submodurl/bare.bench" &&
		bench config -f .benchmodules submodule.bare.path bare
	)
'

test_expect_success 'add should fail when path is used by a file' '
	(
		cd addtest &&
		touch file &&
		test_must_fail	bench submodule add "$submodurl/repo" file
	)
'

test_expect_success 'add should fail when path is used by an existing directory' '
	(
		cd addtest &&
		mkdir empty-dir &&
		test_must_fail bench submodule add "$submodurl/repo" empty-dir
	)
'

test_expect_success 'use superproject as upstream when path is relative and no url is set there' '
	(
		cd addtest &&
		bench submodule add ../repo relative &&
		test "$(bench config -f .benchmodules submodule.relative.url)" = ../repo &&
		bench submodule sync relative &&
		test "$(bench config submodule.relative.url)" = "$submodurl/repo"
	)
'

test_expect_success 'set up for relative path tests' '
	mkdir reltest &&
	(
		cd reltest &&
		bench init &&
		mkdir sub &&
		(
			cd sub &&
			bench init &&
			test_commit foo
		) &&
		bench add sub &&
		bench config -f .benchmodules submodule.sub.path sub &&
		bench config -f .benchmodules submodule.sub.url ../subrepo &&
		cp .bench/config pristine-.bench-config &&
		cp .benchmodules pristine-.benchmodules
	)
'

test_expect_success '../subrepo works with URL - ssh://hostname/repo' '
	(
		cd reltest &&
		cp pristine-.bench-config .bench/config &&
		cp pristine-.benchmodules .benchmodules &&
		bench config remote.origin.url ssh://hostname/repo &&
		bench submodule init &&
		test "$(bench config submodule.sub.url)" = ssh://hostname/subrepo
	)
'

test_expect_success '../subrepo works with port-qualified URL - ssh://hostname:22/repo' '
	(
		cd reltest &&
		cp pristine-.bench-config .bench/config &&
		cp pristine-.benchmodules .benchmodules &&
		bench config remote.origin.url ssh://hostname:22/repo &&
		bench submodule init &&
		test "$(bench config submodule.sub.url)" = ssh://hostname:22/subrepo
	)
'

# About the choice of the path in the next test:
# - double-slash side-steps path mangling issues on Windows
# - it is still an absolute local path
# - there cannot be a server with a blank in its name just in case the
#   path is used erroneously to access a //server/share style path
test_expect_success '../subrepo path works with local path - //somewhere else/repo' '
	(
		cd reltest &&
		cp pristine-.bench-config .bench/config &&
		cp pristine-.benchmodules .benchmodules &&
		bench config remote.origin.url "//somewhere else/repo" &&
		bench submodule init &&
		test "$(bench config submodule.sub.url)" = "//somewhere else/subrepo"
	)
'

test_expect_success '../subrepo works with file URL - file:///tmp/repo' '
	(
		cd reltest &&
		cp pristine-.bench-config .bench/config &&
		cp pristine-.benchmodules .benchmodules &&
		bench config remote.origin.url file:///tmp/repo &&
		bench submodule init &&
		test "$(bench config submodule.sub.url)" = file:///tmp/subrepo
	)
'

test_expect_success '../subrepo works with helper URL- helper:://hostname/repo' '
	(
		cd reltest &&
		cp pristine-.bench-config .bench/config &&
		cp pristine-.benchmodules .benchmodules &&
		bench config remote.origin.url helper:://hostname/repo &&
		bench submodule init &&
		test "$(bench config submodule.sub.url)" = helper:://hostname/subrepo
	)
'

test_expect_success '../subrepo works with scp-style URL - user@host:repo' '
	(
		cd reltest &&
		cp pristine-.bench-config .bench/config &&
		bench config remote.origin.url user@host:repo &&
		bench submodule init &&
		test "$(bench config submodule.sub.url)" = user@host:subrepo
	)
'

test_expect_success '../subrepo works with scp-style URL - user@host:path/to/repo' '
	(
		cd reltest &&
		cp pristine-.bench-config .bench/config &&
		cp pristine-.benchmodules .benchmodules &&
		bench config remote.origin.url user@host:path/to/repo &&
		bench submodule init &&
		test "$(bench config submodule.sub.url)" = user@host:path/to/subrepo
	)
'

test_expect_success '../subrepo works with relative local path - foo' '
	(
		cd reltest &&
		cp pristine-.bench-config .bench/config &&
		cp pristine-.benchmodules .benchmodules &&
		bench config remote.origin.url foo &&
		# actual: fails with an error
		bench submodule init &&
		test "$(bench config submodule.sub.url)" = subrepo
	)
'

test_expect_success '../subrepo works with relative local path - foo/bar' '
	(
		cd reltest &&
		cp pristine-.bench-config .bench/config &&
		cp pristine-.benchmodules .benchmodules &&
		bench config remote.origin.url foo/bar &&
		bench submodule init &&
		test "$(bench config submodule.sub.url)" = foo/subrepo
	)
'

test_expect_success '../subrepo works with relative local path - ./foo' '
	(
		cd reltest &&
		cp pristine-.bench-config .bench/config &&
		cp pristine-.benchmodules .benchmodules &&
		bench config remote.origin.url ./foo &&
		bench submodule init &&
		test "$(bench config submodule.sub.url)" = subrepo
	)
'

test_expect_success '../subrepo works with relative local path - ./foo/bar' '
	(
		cd reltest &&
		cp pristine-.bench-config .bench/config &&
		cp pristine-.benchmodules .benchmodules &&
		bench config remote.origin.url ./foo/bar &&
		bench submodule init &&
		test "$(bench config submodule.sub.url)" = foo/subrepo
	)
'

test_expect_success '../subrepo works with relative local path - ../foo' '
	(
		cd reltest &&
		cp pristine-.bench-config .bench/config &&
		cp pristine-.benchmodules .benchmodules &&
		bench config remote.origin.url ../foo &&
		bench submodule init &&
		test "$(bench config submodule.sub.url)" = ../subrepo
	)
'

test_expect_success '../subrepo works with relative local path - ../foo/bar' '
	(
		cd reltest &&
		cp pristine-.bench-config .bench/config &&
		cp pristine-.benchmodules .benchmodules &&
		bench config remote.origin.url ../foo/bar &&
		bench submodule init &&
		test "$(bench config submodule.sub.url)" = ../foo/subrepo
	)
'

test_expect_success '../bar/a/b/c works with relative local path - ../foo/bar.bench' '
	(
		cd reltest &&
		cp pristine-.bench-config .bench/config &&
		cp pristine-.benchmodules .benchmodules &&
		mkdir -p a/b/c &&
		(cd a/b/c && bench init && test_commit msg) &&
		bench config remote.origin.url ../foo/bar.bench &&
		bench submodule add ../bar/a/b/c ./a/b/c &&
		bench submodule init &&
		test "$(bench config submodule.a/b/c.url)" = ../foo/bar/a/b/c
	)
'

test_expect_success 'moving the superproject does not break submodules' '
	(
		cd addtest &&
		bench submodule status >expect
	) &&
	mv addtest addtest2 &&
	(
		cd addtest2 &&
		bench submodule status >actual &&
		test_cmp expect actual
	)
'

test_expect_success 'moving the submodule does not break the superproject' '
	(
		cd addtest2 &&
		bench submodule status
	) >actual &&
	sed -e "s/^ \([^ ]* repo\) .*/-\1/" <actual >expect &&
	mv addtest2/repo addtest2/repo.bak &&
	test_when_finished "mv addtest2/repo.bak addtest2/repo" &&
	(
		cd addtest2 &&
		bench submodule status
	) >actual &&
	test_cmp expect actual
'

test_expect_success 'submodule add --name allows to replace a submodule with another at the same path' '
	(
		cd addtest2 &&
		(
			cd repo &&
			echo "$submodurl/repo" >expect &&
			bench config remote.origin.url >actual &&
			test_cmp expect actual &&
			echo "gitdir: ../.bench/modules/repo" >expect &&
			test_cmp expect .bench
		) &&
		rm -rf repo &&
		bench rm repo &&
		bench submodule add -q --name repo_new "$submodurl/bare.bench" repo >actual &&
		test_must_be_empty actual &&
		echo "gitdir: ../.bench/modules/submod" >expect &&
		test_cmp expect submod/.bench &&
		(
			cd repo &&
			echo "$submodurl/bare.bench" >expect &&
			bench config remote.origin.url >actual &&
			test_cmp expect actual &&
			echo "gitdir: ../.bench/modules/repo_new" >expect &&
			test_cmp expect .bench
		) &&
		echo "repo" >expect &&
		test_must_fail bench config -f .benchmodules submodule.repo.path &&
		bench config -f .benchmodules submodule.repo_new.path >actual &&
		test_cmp expect actual &&
		echo "$submodurl/repo" >expect &&
		test_must_fail bench config -f .benchmodules submodule.repo.url &&
		echo "$submodurl/bare.bench" >expect &&
		bench config -f .benchmodules submodule.repo_new.url >actual &&
		test_cmp expect actual &&
		echo "$submodurl/repo" >expect &&
		bench config submodule.repo.url >actual &&
		test_cmp expect actual &&
		echo "$submodurl/bare.bench" >expect &&
		bench config submodule.repo_new.url >actual &&
		test_cmp expect actual
	)
'

test_expect_success 'recursive relative submodules stay relative' '
	test_when_finished "rm -rf super clone2 subsub sub3" &&
	mkdir subsub &&
	(
		cd subsub &&
		bench init &&
		>t &&
		bench add t &&
		bench commit -m "initial commit"
	) &&
	mkdir sub3 &&
	(
		cd sub3 &&
		bench init &&
		>t &&
		bench add t &&
		bench commit -m "initial commit" &&
		bench submodule add ../subsub dirdir/subsub &&
		bench commit -m "add submodule subsub"
	) &&
	mkdir super &&
	(
		cd super &&
		bench init &&
		>t &&
		bench add t &&
		bench commit -m "initial commit" &&
		bench submodule add ../sub3 &&
		bench commit -m "add submodule sub"
	) &&
	bench clone super clone2 &&
	(
		cd clone2 &&
		bench submodule update --init --recursive &&
		echo "gitdir: ../.bench/modules/sub3" >./sub3/.bench_expect &&
		echo "gitdir: ../../../.bench/modules/sub3/modules/dirdir/subsub" >./sub3/dirdir/subsub/.bench_expect
	) &&
	test_cmp clone2/sub3/.bench_expect clone2/sub3/.bench &&
	test_cmp clone2/sub3/dirdir/subsub/.bench_expect clone2/sub3/dirdir/subsub/.bench
'

test_expect_success 'submodule add with an existing name fails unless forced' '
	(
		cd addtest2 &&
		rm -rf repo &&
		bench rm repo &&
		test_must_fail bench submodule add -q --name repo_new "$submodurl/repo.bench" repo &&
		test ! -d repo &&
		test_must_fail bench config -f .benchmodules submodule.repo_new.path &&
		test_must_fail bench config -f .benchmodules submodule.repo_new.url &&
		echo "$submodurl/bare.bench" >expect &&
		bench config submodule.repo_new.url >actual &&
		test_cmp expect actual &&
		bench submodule add -f -q --name repo_new "$submodurl/repo.bench" repo &&
		test -d repo &&
		echo "repo" >expect &&
		bench config -f .benchmodules submodule.repo_new.path >actual &&
		test_cmp expect actual &&
		echo "$submodurl/repo.bench" >expect &&
		bench config -f .benchmodules submodule.repo_new.url >actual &&
		test_cmp expect actual &&
		echo "$submodurl/repo.bench" >expect &&
		bench config submodule.repo_new.url >actual &&
		test_cmp expect actual
	)
'

test_expect_success 'set up a second submodule' '
	bench submodule add ./init2 example2 &&
	bench commit -m "submodule example2 added"
'

test_expect_success 'submodule deinit works on repository without submodules' '
	test_when_finished "rm -rf newdirectory" &&
	mkdir newdirectory &&
	(
		cd newdirectory &&
		bench init &&
		>file &&
		bench add file &&
		bench commit -m "repo should not be empty" &&
		bench submodule deinit . &&
		bench submodule deinit --all
	)
'

test_expect_success 'submodule deinit should remove the whole submodule section from .bench/config' '
	bench config submodule.example.foo bar &&
	bench config submodule.example2.frotz nitfol &&
	bench submodule deinit init &&
	test -z "$(bench config --get-regexp "submodule\.example\.")" &&
	test -n "$(bench config --get-regexp "submodule\.example2\.")" &&
	test -f example2/.bench &&
	rmdir init
'

test_expect_success 'submodule deinit should unset core.worktree' '
	test_path_is_file .bench/modules/example/config &&
	test_must_fail bench config -f .bench/modules/example/config core.worktree
'

test_expect_success 'submodule deinit from subdirectory' '
	bench submodule update --init &&
	bench config submodule.example.foo bar &&
	mkdir -p sub &&
	(
		cd sub &&
		bench submodule deinit ../init >../output
	) &&
	test_grep "\\.\\./init" output &&
	test -z "$(bench config --get-regexp "submodule\.example\.")" &&
	test -n "$(bench config --get-regexp "submodule\.example2\.")" &&
	test -f example2/.bench &&
	rmdir init
'

test_expect_success 'submodule deinit . deinits all initialized submodules' '
	bench submodule update --init &&
	bench config submodule.example.foo bar &&
	bench config submodule.example2.frotz nitfol &&
	test_must_fail bench submodule deinit &&
	bench submodule deinit . >actual &&
	test -z "$(bench config --get-regexp "submodule\.example\.")" &&
	test -z "$(bench config --get-regexp "submodule\.example2\.")" &&
	test_grep "Cleared directory .init" actual &&
	test_grep "Cleared directory .example2" actual &&
	rmdir init example2
'

test_expect_success 'submodule deinit --all deinits all initialized submodules' '
	bench submodule update --init &&
	bench config submodule.example.foo bar &&
	bench config submodule.example2.frotz nitfol &&
	test_must_fail bench submodule deinit &&
	bench submodule deinit --all >actual &&
	test -z "$(bench config --get-regexp "submodule\.example\.")" &&
	test -z "$(bench config --get-regexp "submodule\.example2\.")" &&
	test_grep "Cleared directory .init" actual &&
	test_grep "Cleared directory .example2" actual &&
	rmdir init example2
'

test_expect_success 'submodule deinit deinits a submodule when its work tree is missing or empty' '
	bench submodule update --init &&
	rm -rf init example2/* example2/.bench &&
	bench submodule deinit init example2 >actual &&
	test -z "$(bench config --get-regexp "submodule\.example\.")" &&
	test -z "$(bench config --get-regexp "submodule\.example2\.")" &&
	test_grep ! "Cleared directory .init" actual &&
	test_grep "Cleared directory .example2" actual &&
	rmdir init
'

test_expect_success 'submodule deinit fails when the submodule contains modifications unless forced' '
	bench submodule update --init &&
	echo X >>init/s &&
	test_must_fail bench submodule deinit init &&
	test -n "$(bench config --get-regexp "submodule\.example\.")" &&
	test -f example2/.bench &&
	bench submodule deinit -f init >actual &&
	test -z "$(bench config --get-regexp "submodule\.example\.")" &&
	test_grep "Cleared directory .init" actual &&
	rmdir init
'

test_expect_success 'submodule deinit fails when the submodule contains untracked files unless forced' '
	bench submodule update --init &&
	echo X >>init/untracked &&
	test_must_fail bench submodule deinit init &&
	test -n "$(bench config --get-regexp "submodule\.example\.")" &&
	test -f example2/.bench &&
	bench submodule deinit -f init >actual &&
	test -z "$(bench config --get-regexp "submodule\.example\.")" &&
	test_grep "Cleared directory .init" actual &&
	rmdir init
'

test_expect_success 'submodule deinit fails when the submodule HEAD does not match unless forced' '
	bench submodule update --init &&
	(
		cd init &&
		bench checkout HEAD^
	) &&
	test_must_fail bench submodule deinit init &&
	test -n "$(bench config --get-regexp "submodule\.example\.")" &&
	test -f example2/.bench &&
	bench submodule deinit -f init >actual &&
	test -z "$(bench config --get-regexp "submodule\.example\.")" &&
	test_grep "Cleared directory .init" actual &&
	rmdir init
'

test_expect_success 'submodule deinit is silent when used on an uninitialized submodule' '
	bench submodule update --init &&
	bench submodule deinit init >actual &&
	test_grep "Submodule .example. (.*) unregistered for path .init" actual &&
	test_grep "Cleared directory .init" actual &&
	bench submodule deinit init >actual &&
	test_grep ! "Submodule .example. (.*) unregistered for path .init" actual &&
	test_grep "Cleared directory .init" actual &&
	bench submodule deinit . >actual &&
	test_grep ! "Submodule .example. (.*) unregistered for path .init" actual &&
	test_grep "Submodule .example2. (.*) unregistered for path .example2" actual &&
	test_grep "Cleared directory .init" actual &&
	bench submodule deinit . >actual &&
	test_grep ! "Submodule .example. (.*) unregistered for path .init" actual &&
	test_grep ! "Submodule .example2. (.*) unregistered for path .example2" actual &&
	test_grep "Cleared directory .init" actual &&
	bench submodule deinit --all >actual &&
	test_grep ! "Submodule .example. (.*) unregistered for path .init" actual &&
	test_grep ! "Submodule .example2. (.*) unregistered for path .example2" actual &&
	test_grep "Cleared directory .init" actual &&
	rmdir init example2
'

test_expect_success 'submodule deinit absorbs .bench directory if .bench is a directory' '
	bench submodule update --init &&
	(
		cd init &&
		rm .bench &&
		mv ../.bench/modules/example .bench &&
		GIT_WORK_TREE=. bench config --unset core.worktree
	) &&
	bench submodule deinit init &&
	test_path_is_missing init/.bench &&
	test -z "$(bench config --get-regexp "submodule\.example\.")"
'

test_expect_success 'submodule with UTF-8 name' '
	svname=$(printf "\303\245 \303\244\303\266") &&
	mkdir "$svname" &&
	(
		cd "$svname" &&
		bench init &&
		>sub &&
		bench add sub &&
		bench commit -m "init sub"
	) &&
	bench submodule add ./"$svname" &&
	bench submodule >&2 &&
	test -n "$(bench submodule | grep "$svname")"
'

test_expect_success 'submodule add clone shallow submodule' '
	mkdir super &&
	pwd=$(pwd) &&
	(
		cd super &&
		bench init &&
		bench submodule add --depth=1 file://"$pwd"/example2 submodule &&
		(
			cd submodule &&
			test 1 = $(bench log --oneline | wc -l)
		)
	)
'

test_expect_success 'setup superproject with submodules' '
	bench init sub1 &&
	test_commit -C sub1 test &&
	test_commit -C sub1 test2 &&
	bench init multisuper &&
	bench -C multisuper submodule add ../sub1 sub0 &&
	bench -C multisuper submodule add ../sub1 sub1 &&
	bench -C multisuper submodule add ../sub1 sub2 &&
	bench -C multisuper submodule add ../sub1 sub3 &&
	bench -C multisuper commit -m "add some submodules"
'

cat >expect <<-EOF
-sub0
 sub1 (test2)
 sub2 (test2)
 sub3 (test2)
EOF

test_expect_success 'submodule update --init with a specification' '
	test_when_finished "rm -rf multisuper_clone" &&
	pwd=$(pwd) &&
	bench clone file://"$pwd"/multisuper multisuper_clone &&
	bench -C multisuper_clone submodule update --init . ":(exclude)sub0" &&
	bench -C multisuper_clone submodule status | sed "s/$OID_REGEX //" >actual &&
	test_cmp expect actual
'

test_expect_success 'submodule update --init with submodule.active set' '
	test_when_finished "rm -rf multisuper_clone" &&
	pwd=$(pwd) &&
	bench clone file://"$pwd"/multisuper multisuper_clone &&
	bench -C multisuper_clone config submodule.active "." &&
	bench -C multisuper_clone config --add submodule.active ":(exclude)sub0" &&
	bench -C multisuper_clone submodule update --init &&
	bench -C multisuper_clone submodule status | sed "s/$OID_REGEX //" >actual &&
	test_cmp expect actual
'

test_expect_success 'submodule update and setting submodule.<name>.active' '
	test_when_finished "rm -rf multisuper_clone" &&
	pwd=$(pwd) &&
	bench clone file://"$pwd"/multisuper multisuper_clone &&
	bench -C multisuper_clone config --bool submodule.sub0.active "true" &&
	bench -C multisuper_clone config --bool submodule.sub1.active "false" &&
	bench -C multisuper_clone config --bool submodule.sub2.active "true" &&

	cat >expect <<-\EOF &&
	 sub0 (test2)
	-sub1
	 sub2 (test2)
	-sub3
	EOF
	bench -C multisuper_clone submodule update &&
	bench -C multisuper_clone submodule status | sed "s/$OID_REGEX //" >actual &&
	test_cmp expect actual
'

test_expect_success 'clone active submodule without submodule url set' '
	test_when_finished "rm -rf test/test" &&
	mkdir test &&
	# another dir breaks accidental relative paths still being correct
	bench clone file://"$pwd"/multisuper test/test &&
	(
		cd test/test &&
		bench config submodule.active "." &&

		# do not pass --init flag, as the submodule is already active:
		bench submodule update &&
		bench submodule status >actual_raw &&

		cut -d" " -f3- actual_raw >actual &&
		cat >expect <<-\EOF &&
		sub0 (test2)
		sub1 (test2)
		sub2 (test2)
		sub3 (test2)
		EOF
		test_cmp expect actual
	)
'

test_expect_success 'update submodules without url set in .benchconfig' '
	test_when_finished "rm -rf multisuper_clone" &&
	bench clone file://"$pwd"/multisuper multisuper_clone &&

	bench -C multisuper_clone submodule init &&
	for s in sub0 sub1 sub2 sub3
	do
		key=submodule.$s.url &&
		bench -C multisuper_clone config --local --unset $key &&
		bench -C multisuper_clone config --file .benchmodules --unset $key || return 1
	done &&

	test_must_fail bench -C multisuper_clone submodule update 2>err &&
	grep "cannot clone submodule .sub[0-3]. without a URL" err
'

test_expect_success 'clone --recurse-submodules with a pathspec works' '
	test_when_finished "rm -rf multisuper_clone" &&
	cat >expected <<-\EOF &&
	 sub0 (test2)
	-sub1
	-sub2
	-sub3
	EOF

	bench clone --recurse-submodules="sub0" multisuper multisuper_clone &&
	bench -C multisuper_clone submodule status | sed "s/$OID_REGEX //" >actual &&
	test_cmp expected actual
'

test_expect_success 'clone with multiple --recurse-submodules options' '
	test_when_finished "rm -rf multisuper_clone" &&
	cat >expect <<-\EOF &&
	-sub0
	 sub1 (test2)
	-sub2
	 sub3 (test2)
	EOF

	bench clone --recurse-submodules="." \
		  --recurse-submodules=":(exclude)sub0" \
		  --recurse-submodules=":(exclude)sub2" \
		  multisuper multisuper_clone &&
	bench -C multisuper_clone submodule status | sed "s/$OID_REGEX //" >actual &&
	test_cmp expect actual
'

test_expect_success 'clone and subsequent updates correctly auto-initialize submodules' '
	test_when_finished "rm -rf multisuper_clone" &&
	cat <<-\EOF >expect &&
	-sub0
	 sub1 (test2)
	-sub2
	 sub3 (test2)
	EOF

	cat <<-\EOF >expect2 &&
	-sub0
	 sub1 (test2)
	-sub2
	 sub3 (test2)
	-sub4
	 sub5 (test2)
	EOF

	bench clone --recurse-submodules="." \
		  --recurse-submodules=":(exclude)sub0" \
		  --recurse-submodules=":(exclude)sub2" \
		  --recurse-submodules=":(exclude)sub4" \
		  multisuper multisuper_clone &&

	bench -C multisuper_clone submodule status | sed "s/$OID_REGEX //" >actual &&
	test_cmp expect actual &&

	bench -C multisuper submodule add ../sub1 sub4 &&
	bench -C multisuper submodule add ../sub1 sub5 &&
	bench -C multisuper commit -m "add more submodules" &&
	# obtain the new superproject
	bench -C multisuper_clone pull &&
	bench -C multisuper_clone submodule update --init &&
	bench -C multisuper_clone submodule status | sed "s/$OID_REGEX //" >actual &&
	test_cmp expect2 actual
'

test_expect_success 'init properly sets the config' '
	test_when_finished "rm -rf multisuper_clone" &&
	bench clone --recurse-submodules="." \
		  --recurse-submodules=":(exclude)sub0" \
		  multisuper multisuper_clone &&

	bench -C multisuper_clone submodule init -- sub0 sub1 &&
	bench -C multisuper_clone config --get submodule.sub0.active &&
	test_must_fail bench -C multisuper_clone config --get submodule.sub1.active
'

test_expect_success 'recursive clone respects -q' '
	test_when_finished "rm -rf multisuper_clone" &&
	bench clone -q --recurse-submodules multisuper multisuper_clone >actual &&
	test_must_be_empty actual
'

test_expect_success '`submodule init` and `init.templateDir`' '
	mkdir -p tmpl/hooks &&
	write_script tmpl/hooks/post-checkout <<-EOF &&
	echo HOOK-RUN >&2
	echo I was here >hook.run
	exit 1
	EOF

	test_config init.templateDir "$(pwd)/tmpl" &&
	test_when_finished \
		"bench config --global --unset init.templateDir || true" &&
	(
		sane_unset GIT_TEMPLATE_DIR &&
		NO_SET_GIT_TEMPLATE_DIR=t &&
		export NO_SET_GIT_TEMPLATE_DIR &&

		bench config --global init.templateDir "$(pwd)/tmpl" &&
		test_must_fail bench submodule \
			add "$submodurl" sub-global 2>err &&
		bench config --global --unset init.templateDir &&
		test_grep HOOK-RUN err &&
		test_path_is_file sub-global/hook.run &&

		bench config init.templateDir "$(pwd)/tmpl" &&
		bench submodule add "$submodurl" sub-local 2>err &&
		bench config --unset init.templateDir &&
		test_grep ! HOOK-RUN err &&
		test_path_is_missing sub-local/hook.run
	)
'

test_done
