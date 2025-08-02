#!/bin/sh

test_description='bench init'

. ./test-lib.sh

check_config () {
	if test_path_is_dir "$1" &&
	   test_path_is_file "$1/config" && test_path_is_dir "$1/refs"
	then
		: happy
	else
		echo "expected a directory $1, a file $1/config and $1/refs"
		return 1
	fi

	if test_have_prereq POSIXPERM && test -x "$1/config"
	then
		echo "$1/config is executable?"
		return 1
	fi

	bare=$(cd "$1" && bench config --bool core.bare)
	worktree=$(cd "$1" && bench config core.worktree) ||
	worktree=unset

	test "$bare" = "$2" && test "$worktree" = "$3" || {
		echo "expected bare=$2 worktree=$3"
		echo "     got bare=$bare worktree=$worktree"
		return 1
	}
}

test_expect_success 'plain' '
	bench init plain &&
	check_config plain/.bench false unset
'

test_expect_success 'plain nested in bare' '
	(
		bench init --bare bare-ancestor.git &&
		cd bare-ancestor.git &&
		mkdir plain-nested &&
		cd plain-nested &&
		bench init
	) &&
	check_config bare-ancestor.git/plain-nested/.bench false unset
'

test_expect_success 'plain through aliased command, outside any bench repo' '
	(
		HOME=$(pwd)/alias-config &&
		export HOME &&
		mkdir alias-config &&
		echo "[alias] aliasedinit = init" >alias-config/.gitconfig &&

		GIT_CEILING_DIRECTORIES=$(pwd) &&
		export GIT_CEILING_DIRECTORIES &&

		mkdir plain-aliased &&
		cd plain-aliased &&
		bench aliasedinit
	) &&
	check_config plain-aliased/.bench false unset
'

test_expect_success 'plain nested through aliased command' '
	(
		bench init plain-ancestor-aliased &&
		cd plain-ancestor-aliased &&
		echo "[alias] aliasedinit = init" >>.bench/config &&
		mkdir plain-nested &&
		cd plain-nested &&
		bench aliasedinit
	) &&
	check_config plain-ancestor-aliased/plain-nested/.bench false unset
'

test_expect_success 'plain nested in bare through aliased command' '
	(
		bench init --bare bare-ancestor-aliased.git &&
		cd bare-ancestor-aliased.git &&
		echo "[alias] aliasedinit = init" >>config &&
		mkdir plain-nested &&
		cd plain-nested &&
		bench aliasedinit
	) &&
	check_config bare-ancestor-aliased.git/plain-nested/.bench false unset
'

test_expect_success 'No extra GIT_* on alias scripts' '
	write_script script <<-\EOF &&
	env |
		sed -n \
			-e "/^GIT_PREFIX=/d" \
			-e "/^GIT_TEXTDOMAINDIR=/d" \
			-e "/^GIT_TRACE2_PARENT/d" \
			-e "/^GIT_/s/=.*//p" |
		sort
	EOF
	./script >expected &&
	bench config alias.script \!./script &&
	( mkdir sub && cd sub && bench script >../actual ) &&
	test_cmp expected actual
'

test_expect_success 'plain with GIT_WORK_TREE' '
	mkdir plain-wt &&
	test_must_fail env GIT_WORK_TREE="$(pwd)/plain-wt" bench init plain-wt
'

test_expect_success 'plain bare' '
	bench --bare init plain-bare-1 &&
	check_config plain-bare-1 true unset
'

test_expect_success 'plain bare with GIT_WORK_TREE' '
	mkdir plain-bare-2 &&
	test_must_fail \
		env GIT_WORK_TREE="$(pwd)/plain-bare-2" \
		bench --bare init plain-bare-2
'

test_expect_success 'GIT_DIR bare' '
	mkdir git-dir-bare.git &&
	GIT_DIR=git-dir-bare.git bench init &&
	check_config git-dir-bare.git true unset
'

test_expect_success 'init --bare' '
	bench init --bare init-bare.git &&
	check_config init-bare.git true unset
'

test_expect_success 'GIT_DIR non-bare' '

	(
		mkdir non-bare &&
		cd non-bare &&
		GIT_DIR=.bench bench init
	) &&
	check_config non-bare/.bench false unset
'

test_expect_success 'GIT_DIR & GIT_WORK_TREE (1)' '

	(
		mkdir git-dir-wt-1.git &&
		GIT_WORK_TREE=$(pwd) GIT_DIR=git-dir-wt-1.git bench init
	) &&
	check_config git-dir-wt-1.git false "$(pwd)"
'

test_expect_success 'GIT_DIR & GIT_WORK_TREE (2)' '
	mkdir git-dir-wt-2.git &&
	test_must_fail env \
		GIT_WORK_TREE="$(pwd)" \
		GIT_DIR=git-dir-wt-2.git \
		bench --bare init
'

test_expect_success 'reinit' '

	(
		mkdir again &&
		cd again &&
		bench -c init.defaultBranch=initial init >out1 2>err1 &&
		bench init >out2 2>err2
	) &&
	test_grep "Initialized empty" again/out1 &&
	test_grep "Reinitialized existing" again/out2 &&
	test_must_be_empty again/err1 &&
	test_must_be_empty again/err2
'

test_expect_success 'init with --template' '
	mkdir template-source &&
	echo content >template-source/file &&
	bench init --template=template-source template-custom &&
	test_cmp template-source/file template-custom/.bench/file
'

test_expect_success 'init with --template (blank)' '
	bench init template-plain &&
	test_path_is_file template-plain/.bench/info/exclude &&
	bench init --template= template-blank &&
	test_path_is_missing template-blank/.bench/info/exclude
'

init_no_templatedir_env () {
	(
		sane_unset GIT_TEMPLATE_DIR &&
		NO_SET_GIT_TEMPLATE_DIR=t &&
		export NO_SET_GIT_TEMPLATE_DIR &&
		bench init "$1"
	)
}

test_expect_success 'init with init.templatedir set' '
	mkdir templatedir-source &&
	echo Content >templatedir-source/file &&
	test_config_global init.templatedir "${HOME}/templatedir-source" &&

	init_no_templatedir_env templatedir-set &&
	test_cmp templatedir-source/file templatedir-set/.bench/file
'

test_expect_success 'init with init.templatedir using ~ expansion' '
	mkdir -p templatedir-source &&
	echo Content >templatedir-source/file &&
	test_config_global init.templatedir "~/templatedir-source" &&

	init_no_templatedir_env templatedir-expansion &&
	test_cmp templatedir-source/file templatedir-expansion/.bench/file
'

test_expect_success 'init --bare/--shared overrides system/global config' '
	test_config_global core.bare false &&
	test_config_global core.sharedRepository 0640 &&
	bench init --bare --shared=0666 init-bare-shared-override &&
	check_config init-bare-shared-override true unset &&
	test x0666 = \
	x$(bench config -f init-bare-shared-override/config core.sharedRepository)
'

test_expect_success 'init honors global core.sharedRepository' '
	test_config_global core.sharedRepository 0666 &&
	bench init shared-honor-global &&
	test x0666 = \
	x$(bench config -f shared-honor-global/.bench/config core.sharedRepository)
'

test_expect_success 'init allows insanely long --template' '
	bench init --template=$(printf "x%09999dx" 1) test
'

test_expect_success 'init creates a new directory' '
	rm -fr newdir &&
	bench init newdir &&
	test_path_is_dir newdir/.bench/refs
'

test_expect_success 'init creates a new bare directory' '
	rm -fr newdir &&
	bench init --bare newdir &&
	test_path_is_dir newdir/refs
'

test_expect_success 'init recreates a directory' '
	rm -fr newdir &&
	mkdir newdir &&
	bench init newdir &&
	test_path_is_dir newdir/.bench/refs
'

test_expect_success 'init recreates a new bare directory' '
	rm -fr newdir &&
	mkdir newdir &&
	bench init --bare newdir &&
	test_path_is_dir newdir/refs
'

test_expect_success 'init creates a new deep directory' '
	rm -fr newdir &&
	bench init newdir/a/b/c &&
	test_path_is_dir newdir/a/b/c/.bench/refs
'

test_expect_success POSIXPERM 'init creates a new deep directory (umask vs. shared)' '
	rm -fr newdir &&
	(
		# Leading directories should honor umask while
		# the repository itself should follow "shared"
		mkdir newdir &&
		# Remove a default ACL if possible.
		(setfacl -k newdir 2>/dev/null || true) &&
		umask 002 &&
		bench init --bare --shared=0660 newdir/a/b/c &&
		test_path_is_dir newdir/a/b/c/refs &&
		ls -ld newdir/a newdir/a/b > lsab.out &&
		! grep -v "^drwxrw[sx]r-x" lsab.out &&
		ls -ld newdir/a/b/c > lsc.out &&
		! grep -v "^drwxrw[sx]---" lsc.out
	)
'

test_expect_success 'init notices EEXIST (1)' '
	rm -fr newdir &&
	>newdir &&
	test_must_fail bench init newdir &&
	test_path_is_file newdir
'

test_expect_success 'init notices EEXIST (2)' '
	rm -fr newdir &&
	mkdir newdir &&
	>newdir/a &&
	test_must_fail bench init newdir/a/b &&
	test_path_is_file newdir/a
'

test_expect_success POSIXPERM,SANITY 'init notices EPERM' '
	test_when_finished "chmod +w newdir" &&
	rm -fr newdir &&
	mkdir newdir &&
	chmod -w newdir &&
	test_must_fail bench init newdir/a/b
'

test_expect_success 'init creates a new bare directory with global --bare' '
	rm -rf newdir &&
	bench --bare init newdir &&
	test_path_is_dir newdir/refs
'

test_expect_success 'init prefers command line to GIT_DIR' '
	rm -rf newdir &&
	mkdir otherdir &&
	GIT_DIR=otherdir bench --bare init newdir &&
	test_path_is_dir newdir/refs &&
	test_path_is_missing otherdir/refs
'

test_expect_success 'init with separate gitdir' '
	rm -rf newdir &&
	bench init --separate-git-dir realgitdir newdir &&
	newdir_git="$(cat newdir/.bench)" &&
	test_cmp_fspath "$(pwd)/realgitdir" "${newdir_git#gitdir: }" &&
	test_path_is_dir realgitdir/refs
'

test_expect_success 'explicit bare & --separate-git-dir incompatible' '
	test_must_fail bench init --bare --separate-git-dir goop.git bare.git 2>err &&
	test_grep "cannot be used together" err
'

test_expect_success 'implicit bare & --separate-git-dir incompatible' '
	test_when_finished "rm -rf bare.git" &&
	mkdir -p bare.git &&
	test_must_fail env GIT_DIR=. \
		bench -C bare.git init --separate-git-dir goop.git 2>err &&
	test_grep "incompatible" err
'

test_expect_success 'bare & --separate-git-dir incompatible within worktree' '
	test_when_finished "rm -rf bare.git linkwt seprepo" &&
	test_commit gumby &&
	bench clone --bare . bare.git &&
	bench -C bare.git worktree add --detach ../linkwt &&
	test_must_fail bench -C linkwt init --separate-git-dir seprepo 2>err &&
	test_grep "incompatible" err
'

test_lazy_prereq GETCWD_IGNORES_PERMS '
	base=GETCWD_TEST_BASE_DIR &&
	mkdir -p $base/dir &&
	chmod 100 $base ||
	BUG "cannot prepare $base"

	(
		cd $base/dir &&
		test-tool getcwd
	)
	status=$?

	chmod 700 $base &&
	rm -rf $base ||
	BUG "cannot clean $base"
	return $status
'

check_long_base_path () {
	# exceed initial buffer size of strbuf_getcwd()
	component=123456789abcdef &&
	test_when_finished "chmod 0700 $component; rm -rf $component" &&
	p31=$component/$component &&
	p127=$p31/$p31/$p31/$p31 &&
	mkdir -p $p127 &&
	if test $# = 1
	then
		chmod $1 $component
	fi &&
	(
		cd $p127 &&
		bench init newdir
	)
}

test_expect_success 'init in long base path' '
	check_long_base_path
'

test_expect_success GETCWD_IGNORES_PERMS 'init in long restricted base path' '
	check_long_base_path 0111
'

test_expect_success 're-init on .bench file' '
	( cd newdir && bench init )
'

test_expect_success 're-init to update git link' '
	bench -C newdir init --separate-git-dir ../surrealgitdir &&
	newdir_git="$(cat newdir/.bench)" &&
	test_cmp_fspath "$(pwd)/surrealgitdir" "${newdir_git#gitdir: }" &&
	test_path_is_dir surrealgitdir/refs &&
	test_path_is_missing realgitdir/refs
'

test_expect_success 're-init to move gitdir' '
	rm -rf newdir realgitdir surrealgitdir &&
	bench init newdir &&
	bench -C newdir init --separate-git-dir ../realgitdir &&
	newdir_git="$(cat newdir/.bench)" &&
	test_cmp_fspath "$(pwd)/realgitdir" "${newdir_git#gitdir: }" &&
	test_path_is_dir realgitdir/refs
'

test_expect_success SYMLINKS 're-init to move gitdir symlink' '
	rm -rf newdir realgitdir &&
	bench init newdir &&
	(
	cd newdir &&
	mv .bench here &&
	ln -s here .bench &&
	bench init --separate-git-dir ../realgitdir
	) &&
	echo "gitdir: $(pwd)/realgitdir" >expected &&
	test_cmp expected newdir/.bench &&
	test_cmp expected newdir/here &&
	test_path_is_dir realgitdir/refs
'

sep_git_dir_worktree ()  {
	test_when_finished "rm -rf mainwt linkwt seprepo" &&
	bench init mainwt &&
	if test "relative" = $2
	then
		test_config -C mainwt worktree.useRelativePaths true
	else
		test_config -C mainwt worktree.useRelativePaths false
	fi
	test_commit -C mainwt gumby &&
	bench -C mainwt worktree add --detach ../linkwt &&
	bench -C "$1" init --separate-git-dir ../seprepo &&
	bench -C mainwt rev-parse --git-common-dir >expect &&
	bench -C linkwt rev-parse --git-common-dir >actual &&
	test_cmp expect actual
}

test_expect_success 're-init to move gitdir with linked worktrees (absolute)' '
	sep_git_dir_worktree mainwt absolute
'

test_expect_success 're-init to move gitdir within linked worktree (absolute)' '
	sep_git_dir_worktree linkwt absolute
'

test_expect_success 're-init to move gitdir with linked worktrees (relative)' '
	sep_git_dir_worktree mainwt relative
'

test_expect_success 're-init to move gitdir within linked worktree (relative)' '
	sep_git_dir_worktree linkwt relative
'

test_expect_success MINGW '.bench hidden' '
	rm -rf newdir &&
	(
		sane_unset GIT_DIR GIT_WORK_TREE &&
		mkdir newdir &&
		cd newdir &&
		bench init &&
		test_path_is_hidden .bench
	) &&
	check_config newdir/.bench false unset
'

test_expect_success MINGW 'bare git dir not hidden' '
	rm -rf newdir &&
	(
		sane_unset GIT_DIR GIT_WORK_TREE GIT_CONFIG &&
		mkdir newdir &&
		cd newdir &&
		bench --bare init
	) &&
	! is_hidden newdir
'

test_expect_success 'remote init from does not use config from cwd' '
	rm -rf newdir &&
	test_config core.logallrefupdates true &&
	bench init newdir &&
	echo true >expect &&
	bench -C newdir config --bool core.logallrefupdates >actual &&
	test_cmp expect actual
'

test_expect_success 're-init from a linked worktree' '
	bench init main-worktree &&
	(
		cd main-worktree &&
		test_commit first &&
		bench worktree add ../linked-worktree &&
		mv .bench/info/exclude expected-exclude &&
		cp .bench/config expected-config &&
		find .bench/worktrees -print | sort >expected &&
		bench -C ../linked-worktree init &&
		test_cmp expected-exclude .bench/info/exclude &&
		test_cmp expected-config .bench/config &&
		find .bench/worktrees -print | sort >actual &&
		test_cmp expected actual
	)
'

test_expect_success 'init honors GIT_DEFAULT_HASH' '
	test_when_finished "rm -rf sha1 sha256" &&
	GIT_DEFAULT_HASH=sha1 bench init sha1 &&
	bench -C sha1 rev-parse --show-object-format >actual &&
	echo sha1 >expected &&
	test_cmp expected actual &&
	GIT_DEFAULT_HASH=sha256 bench init sha256 &&
	bench -C sha256 rev-parse --show-object-format >actual &&
	echo sha256 >expected &&
	test_cmp expected actual
'

test_expect_success 'init honors --object-format' '
	test_when_finished "rm -rf explicit-sha1 explicit-sha256" &&
	bench init --object-format=sha1 explicit-sha1 &&
	bench -C explicit-sha1 rev-parse --show-object-format >actual &&
	echo sha1 >expected &&
	test_cmp expected actual &&
	bench init --object-format=sha256 explicit-sha256 &&
	bench -C explicit-sha256 rev-parse --show-object-format >actual &&
	echo sha256 >expected &&
	test_cmp expected actual
'

test_expect_success 'init honors init.defaultObjectFormat' '
	test_when_finished "rm -rf sha1 sha256" &&

	test_config_global init.defaultObjectFormat sha1 &&
	(
		sane_unset GIT_DEFAULT_HASH &&
		bench init sha1 &&
		bench -C sha1 rev-parse --show-object-format >actual &&
		echo sha1 >expected &&
		test_cmp expected actual
	) &&

	test_config_global init.defaultObjectFormat sha256 &&
	(
		sane_unset GIT_DEFAULT_HASH &&
		bench init sha256 &&
		bench -C sha256 rev-parse --show-object-format >actual &&
		echo sha256 >expected &&
		test_cmp expected actual
	)
'

test_expect_success 'init warns about invalid init.defaultObjectFormat' '
	test_when_finished "rm -rf repo" &&
	test_config_global init.defaultObjectFormat garbage &&

	echo "warning: unknown hash algorithm ${SQ}garbage${SQ}" >expect &&
	bench init repo 2>err &&
	test_cmp expect err &&

	bench -C repo rev-parse --show-object-format >actual &&
	echo $GIT_DEFAULT_HASH >expected &&
	test_cmp expected actual
'

test_expect_success '--object-format overrides GIT_DEFAULT_HASH' '
	test_when_finished "rm -rf repo" &&
	GIT_DEFAULT_HASH=sha1 bench init --object-format=sha256 repo &&
	bench -C repo rev-parse --show-object-format >actual &&
	echo sha256 >expected
'

test_expect_success 'GIT_DEFAULT_HASH overrides init.defaultObjectFormat' '
	test_when_finished "rm -rf repo" &&
	test_config_global init.defaultObjectFormat sha1 &&
	GIT_DEFAULT_HASH=sha256 bench init repo &&
	bench -C repo rev-parse --show-object-format >actual &&
	echo sha256 >expected
'

for hash in sha1 sha256
do
	test_expect_success "reinit repository with GIT_DEFAULT_HASH=$hash does not change format" '
		test_when_finished "rm -rf repo" &&
		bench init repo &&
		bench -C repo rev-parse --show-object-format >expect &&
		GIT_DEFAULT_HASH=$hash bench init repo &&
		bench -C repo rev-parse --show-object-format >actual &&
		test_cmp expect actual
	'
done

test_expect_success 'extensions.objectFormat is not allowed with repo version 0' '
	test_when_finished "rm -rf explicit-v0" &&
	bench init --object-format=sha256 explicit-v0 &&
	bench -C explicit-v0 config core.repositoryformatversion 0 &&
	test_must_fail bench -C explicit-v0 rev-parse --show-object-format
'

test_expect_success 'init rejects attempts to initialize with different hash' '
	test_must_fail bench -C sha1 init --object-format=sha256 &&
	test_must_fail bench -C sha256 init --object-format=sha1
'

test_expect_success DEFAULT_REPO_FORMAT 'extensions.refStorage is not allowed with repo version 0' '
	test_when_finished "rm -rf refstorage" &&
	bench init refstorage --git-compat &&
	bench -C refstorage config extensions.refStorage files &&
	test_must_fail bench -C refstorage rev-parse 2>err &&
	grep "repo version is 0, but v1-only extension found" err
'

test_expect_success DEFAULT_REPO_FORMAT 'extensions.refStorage with files backend' '
	test_when_finished "rm -rf refstorage" &&
	bench init refstorage &&
	bench -C refstorage config core.repositoryformatversion 1 &&
	bench -C refstorage config extensions.refStorage files &&
	test_commit -C refstorage A &&
	bench -C refstorage rev-parse --verify HEAD
'

test_expect_success DEFAULT_REPO_FORMAT 'extensions.refStorage with unknown backend' '
	test_when_finished "rm -rf refstorage" &&
	bench init refstorage &&
	bench -C refstorage config core.repositoryformatversion 1 &&
	bench -C refstorage config extensions.refStorage garbage &&
	test_must_fail bench -C refstorage rev-parse 2>err &&
	grep "invalid value for ${SQ}extensions.refstorage${SQ}: ${SQ}garbage${SQ}" err
'

test_expect_success 'init with GIT_DEFAULT_REF_FORMAT=garbage' '
	test_when_finished "rm -rf refformat" &&
	cat >expect <<-EOF &&
	fatal: unknown ref storage format ${SQ}garbage${SQ}
	EOF
	test_must_fail env GIT_DEFAULT_REF_FORMAT=garbage bench init refformat 2>err &&
	test_cmp expect err
'

test_expect_success 'init warns about invalid init.defaultRefFormat' '
	test_when_finished "rm -rf repo" &&
	test_config_global init.defaultRefFormat garbage &&

	echo "warning: unknown ref storage format ${SQ}garbage${SQ}" >expect &&
	bench init repo 2>err &&
	test_cmp expect err &&

	bench -C repo rev-parse --show-ref-format >actual &&
	echo $GIT_DEFAULT_REF_FORMAT >expected &&
	test_cmp expected actual
'

test_expect_success 'default ref format' '
	test_when_finished "rm -rf refformat" &&
	(
		sane_unset GIT_DEFAULT_REF_FORMAT &&
		bench init refformat
	) &&
	bench version --build-options | sed -ne "s/^default-ref-format: //p" >expect &&
	bench -C refformat rev-parse --show-ref-format >actual &&
	test_cmp expect actual
'

backends="files reftable"
for format in $backends
do
	test_expect_success DEFAULT_REPO_FORMAT "init with GIT_DEFAULT_REF_FORMAT=$format" '
		test_when_finished "rm -rf refformat" &&
		GIT_DEFAULT_REF_FORMAT=$format bench init refformat &&

		if test $format = files
		then
			test_must_fail bench -C refformat config extensions.refstorage &&
			# Bench always uses version 1 for extensions support
			echo 1 >expect
		else
			bench -C refformat config extensions.refstorage &&
			echo 1 >expect
		fi &&
		bench -C refformat config core.repositoryformatversion >actual &&
		test_cmp expect actual &&

		echo $format >expect &&
		bench -C refformat rev-parse --show-ref-format >actual &&
		test_cmp expect actual
	'

	test_expect_success "init with --ref-format=$format" '
		test_when_finished "rm -rf refformat" &&
		bench init --ref-format=$format refformat &&
		echo $format >expect &&
		bench -C refformat rev-parse --show-ref-format >actual &&
		test_cmp expect actual
	'

	test_expect_success "init with init.defaultRefFormat=$format" '
		test_when_finished "rm -rf refformat" &&
		test_config_global init.defaultRefFormat $format &&
		(
			sane_unset GIT_DEFAULT_REF_FORMAT &&
			bench init refformat
		) &&

		echo $format >expect &&
		bench -C refformat rev-parse --show-ref-format >actual &&
		test_cmp expect actual
	'

	test_expect_success "--ref-format=$format overrides GIT_DEFAULT_REF_FORMAT" '
		test_when_finished "rm -rf refformat" &&
		GIT_DEFAULT_REF_FORMAT=garbage bench init --ref-format=$format refformat &&
		echo $format >expect &&
		bench -C refformat rev-parse --show-ref-format >actual &&
		test_cmp expect actual
	'

	test_expect_success "reinit repository with GIT_DEFAULT_REF_FORMAT=$format does not change format" '
		test_when_finished "rm -rf refformat" &&
		bench init refformat &&
		bench -C refformat rev-parse --show-ref-format >expect &&
		GIT_DEFAULT_REF_FORMAT=$format bench init refformat &&
		bench -C refformat rev-parse --show-ref-format >actual &&
		test_cmp expect actual
	'
done

test_expect_success "--ref-format= overrides GIT_DEFAULT_REF_FORMAT" '
	test_when_finished "rm -rf refformat" &&
	GIT_DEFAULT_REF_FORMAT=files bench init --ref-format=reftable refformat &&
	echo reftable >expect &&
	bench -C refformat rev-parse --show-ref-format >actual &&
	test_cmp expect actual
'

test_expect_success "GIT_DEFAULT_REF_FORMAT= overrides init.defaultRefFormat" '
	test_when_finished "rm -rf refformat" &&
	test_config_global init.defaultRefFormat files &&

	GIT_DEFAULT_REF_FORMAT=reftable bench init refformat &&
	echo reftable >expect &&
	bench -C refformat rev-parse --show-ref-format >actual &&
	test_cmp expect actual
'

test_expect_success "init with feature.experimental=true" '
	test_when_finished "rm -rf refformat" &&
	test_config_global feature.experimental true &&
	(
		sane_unset GIT_DEFAULT_REF_FORMAT &&
		bench init refformat
	) &&
	echo reftable >expect &&
	bench -C refformat rev-parse --show-ref-format >actual &&
	test_cmp expect actual
'

test_expect_success "init.defaultRefFormat overrides feature.experimental=true" '
	test_when_finished "rm -rf refformat" &&
	test_config_global feature.experimental true &&
	test_config_global init.defaultRefFormat files &&
	(
		sane_unset GIT_DEFAULT_REF_FORMAT &&
		bench init refformat
	) &&
	echo files >expect &&
	bench -C refformat rev-parse --show-ref-format >actual &&
	test_cmp expect actual
'

test_expect_success "GIT_DEFAULT_REF_FORMAT= overrides feature.experimental=true" '
	test_when_finished "rm -rf refformat" &&
	test_config_global feature.experimental true &&
	GIT_DEFAULT_REF_FORMAT=files bench init refformat &&
	echo files >expect &&
	bench -C refformat rev-parse --show-ref-format >actual &&
	test_cmp expect actual
'

for from_format in $backends
do
	test_expect_success "re-init with same format ($from_format)" '
		test_when_finished "rm -rf refformat" &&
		bench init --ref-format=$from_format refformat &&
		bench init --ref-format=$from_format refformat &&
		echo $from_format >expect &&
		bench -C refformat rev-parse --show-ref-format >actual &&
		test_cmp expect actual
	'

	for to_format in $backends
	do
		if test "$from_format" = "$to_format"
		then
			continue
		fi

		test_expect_success "re-init with different format fails ($from_format -> $to_format)" '
			test_when_finished "rm -rf refformat" &&
			bench init --ref-format=$from_format refformat &&
			cat >expect <<-EOF &&
			fatal: attempt to reinitialize repository with different reference storage format
			EOF
			test_must_fail bench init --ref-format=$to_format refformat 2>err &&
			test_cmp expect err &&
			echo $from_format >expect &&
			bench -C refformat rev-parse --show-ref-format >actual &&
			test_cmp expect actual
		'
	done
done

test_expect_success 'init with --ref-format=garbage' '
	test_when_finished "rm -rf refformat" &&
	cat >expect <<-EOF &&
	fatal: unknown ref storage format ${SQ}garbage${SQ}
	EOF
	test_must_fail bench init --ref-format=garbage refformat 2>err &&
	test_cmp expect err
'

test_expect_success MINGW 'core.hidedotfiles = false' '
	bench config --global core.hidedotfiles false &&
	rm -rf newdir &&
	mkdir newdir &&
	(
		sane_unset GIT_DIR GIT_WORK_TREE GIT_CONFIG &&
		bench -C newdir init
	) &&
	! is_hidden newdir/.bench
'

test_expect_success MINGW 'redirect std handles' '
	GIT_REDIRECT_STDOUT=output.txt bench rev-parse --git-dir &&
	test .git = "$(cat output.txt)" &&
	test -z "$(GIT_REDIRECT_STDOUT=off bench rev-parse --git-dir)" &&
	test_must_fail env \
		GIT_REDIRECT_STDOUT=output.txt \
		GIT_REDIRECT_STDERR="2>&1" \
		git rev-parse --git-dir --verify refs/invalid &&
	grep "^\\.git\$" output.txt &&
	grep "Needed a single revision" output.txt
'

test_expect_success '--initial-branch' '
	bench init --initial-branch=hello initial-branch-option &&
	bench -C initial-branch-option symbolic-ref HEAD >actual &&
	echo refs/heads/hello >expect &&
	test_cmp expect actual &&

	: re-initializing should not change the branch name &&
	bench init --initial-branch=ignore initial-branch-option 2>err &&
	test_grep "ignored --initial-branch" err &&
	bench -C initial-branch-option symbolic-ref HEAD >actual &&
	grep hello actual
'

test_expect_success 'overridden default initial branch name (config)' '
	test_config_global init.defaultBranch nmb &&
	GIT_TEST_DEFAULT_INITIAL_BRANCH_NAME= bench init initial-branch-config &&
	bench -C initial-branch-config symbolic-ref HEAD >actual &&
	grep nmb actual
'

test_expect_success 'advice on unconfigured init.defaultBranch' '
	GIT_TEST_DEFAULT_INITIAL_BRANCH_NAME= bench -c color.advice=always \
		init unconfigured-default-branch-name 2>err &&
	test_decode_color <err >decoded &&
	test_grep "<YELLOW>hint: " decoded
'

test_expect_success 'advice on unconfigured init.defaultBranch disabled' '
	test_when_finished "rm -rf no-advice" &&

	GIT_TEST_DEFAULT_INITIAL_BRANCH_NAME= \
		bench -c advice.defaultBranchName=false init no-advice 2>err &&
	test_grep ! "hint: " err
'

test_expect_success 'overridden default main branch name (env)' '
	test_config_global init.defaultBranch nmb &&
	GIT_TEST_DEFAULT_INITIAL_BRANCH_NAME=env bench init main-branch-env &&
	bench -C main-branch-env symbolic-ref HEAD >actual &&
	grep env actual
'

test_expect_success 'invalid default branch name' '
	test_must_fail env GIT_TEST_DEFAULT_INITIAL_BRANCH_NAME="with space" \
		bench init initial-branch-invalid 2>err &&
	test_grep "invalid branch name" err
'

test_expect_success 'branch -m with the initial branch' '
	bench init rename-initial &&
	bench -C rename-initial branch -m renamed &&
	echo renamed >expect &&
	bench -C rename-initial symbolic-ref --short HEAD >actual &&
	test_cmp expect actual &&

	bench -C rename-initial branch -m renamed again &&
	echo again >expect &&
	bench -C rename-initial symbolic-ref --short HEAD >actual &&
	test_cmp expect actual
'

test_expect_success 'init with includeIf.onbranch condition' '
	test_when_finished "rm -rf repo" &&
	bench -c includeIf.onbranch:main.path=nonexistent init repo &&
	echo $GIT_DEFAULT_REF_FORMAT >expect &&
	bench -C repo rev-parse --show-ref-format >actual &&
	test_cmp expect actual
'

test_expect_success 'init with includeIf.onbranch condition with existing directory' '
	test_when_finished "rm -rf repo" &&
	mkdir repo &&
	bench -c includeIf.onbranch:nonexistent.path=/does/not/exist init repo &&
	echo $GIT_DEFAULT_REF_FORMAT >expect &&
	bench -C repo rev-parse --show-ref-format >actual &&
	test_cmp expect actual
'

test_expect_success 're-init with includeIf.onbranch condition' '
	test_when_finished "rm -rf repo" &&
	bench init repo &&
	bench -c includeIf.onbranch:nonexistent.path=/does/not/exist init repo &&
	echo $GIT_DEFAULT_REF_FORMAT >expect &&
	bench -C repo rev-parse --show-ref-format >actual &&
	test_cmp expect actual
'

test_expect_success 're-init skips non-matching includeIf.onbranch' '
	test_when_finished "rm -rf repo config" &&
	cat >config <<-EOF &&
	[
	garbage
	EOF
	bench init repo &&
	bench -c includeIf.onbranch:nonexistent.path="$(test-tool path-utils absolute_path config)" init repo
'

test_expect_success 're-init reads matching includeIf.onbranch' '
	test_when_finished "rm -rf repo config" &&
	cat >config <<-EOF &&
	[
	garbage
	EOF
	path="$(test-tool path-utils absolute_path config)" &&
	bench init --initial-branch=branch repo &&
	cat >expect <<-EOF &&
	fatal: bad config line 1 in file $path
	EOF
	test_must_fail bench -c includeIf.onbranch:branch.path="$path" init repo 2>err &&
	test_cmp expect err
'

test_done
