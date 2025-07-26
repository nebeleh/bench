#!/bin/sh

test_description='help'

. ./test-lib.sh

configure_help () {
	test_config help.format html &&

	# Unless the path has "://" in it, Git tries to make sure
	# the documentation directory locally exists. Avoid it as
	# we are only interested in seeing an attempt to correctly
	# invoke a help browser in this test.
	test_config help.htmlpath test://html &&

	# Name a custom browser
	test_config browser.test.cmd ./test-browser &&
	test_config help.browser test
}

test_expect_success "setup" '
	# Just write out which page gets requested
	write_script test-browser <<-\EOF
	echo "$*" >test-browser.log
	EOF
'

# make sure to exercise these code paths, the output is a bit tricky
# to verify
test_expect_success 'basic help commands' '
	bench help >/dev/null &&
	bench help -a --no-verbose >/dev/null &&
	bench help -g >/dev/null &&
	bench help -a >/dev/null
'

test_expect_success 'invalid usage' '
	test_expect_code 129 bench help -a add &&
	test_expect_code 129 bench help --all add &&

	test_expect_code 129 bench help -g add &&
	test_expect_code 129 bench help -a -c &&

	test_expect_code 129 bench help -g add &&
	test_expect_code 129 bench help -a -g &&

	test_expect_code 129 bench help --user-interfaces add &&

	test_expect_code 129 bench help -g -c &&
	test_expect_code 129 bench help --config-for-completion add &&
	test_expect_code 129 bench help --config-sections-for-completion add
'

for opt in '-a' '-g' '-c' '--config-for-completion' '--config-sections-for-completion'
do
	test_expect_success "invalid usage of '$opt' with [-i|-m|-w]" '
		bench help $opt &&
		test_expect_code 129 bench help $opt -i &&
		test_expect_code 129 bench help $opt -m &&
		test_expect_code 129 bench help $opt -w
	'

	if test "$opt" = "-a"
	then
		continue
	fi

	test_expect_success "invalid usage of '$opt' with --no-external-commands" '
		test_expect_code 129 bench help $opt --no-external-commands
	'

	test_expect_success "invalid usage of '$opt' with --no-aliases" '
		test_expect_code 129 bench help $opt --no-external-commands
	'
done

test_expect_success "works for commands and guides by default" '
	configure_help &&
	bench help status &&
	echo "test://html/bench-status.html" >expect &&
	test_cmp expect test-browser.log &&
	bench help revisions &&
	echo "test://html/benchrevisions.html" >expect &&
	test_cmp expect test-browser.log
'

test_expect_success "--exclude-guides does not work for guides" '
	>test-browser.log &&
	test_must_fail bench help --exclude-guides revisions &&
	test_must_be_empty test-browser.log
'

test_expect_success "--help does not work for guides" "
	cat <<-EOF >expect &&
		bench: 'revisions' is not a bench command. See 'bench --help'.
	EOF
	test_must_fail bench revisions --help 2>actual &&
	test_cmp expect actual
"

test_expect_success 'bench help' '
	bench help >help.output &&
	test_grep "^   clone  " help.output &&
	test_grep "^   add    " help.output &&
	test_grep "^   log    " help.output &&
	test_grep "^   commit " help.output &&
	test_grep "^   fetch  " help.output
'

test_expect_success 'bench help -g' '
	bench help -g >help.output &&
	test_grep "^   everyday   " help.output &&
	test_grep "^   tutorial   " help.output
'

test_expect_success 'bench help fails for non-existing html pages' '
	configure_help &&
	mkdir html-empty &&
	test_must_fail bench -c help.htmlpath=html-empty help status &&
	test_must_be_empty test-browser.log
'

test_expect_success 'bench help succeeds without bench.html' '
	configure_help &&
	mkdir html-with-docs &&
	touch html-with-docs/bench-status.html &&
	bench -c help.htmlpath=html-with-docs help status &&
	echo "html-with-docs/bench-status.html" >expect &&
	test_cmp expect test-browser.log
'

test_expect_success 'bench help --user-interfaces' '
	bench help --user-interfaces >help.output &&
	grep "^   attributes   " help.output &&
	grep "^   mailmap   " help.output
'

test_expect_success 'bench help -c' '
	bench help -c >help.output &&
	cat >expect <<-\EOF &&

	'\''bench help config'\'' for more information
	EOF
	grep -v -E \
		-e "^[^.]+\.[^.]+$" \
		-e "^[^.]+\.[^.]+\.[^.]+$" \
		help.output >actual &&
	test_cmp expect actual
'

test_expect_success 'bench help --config-for-completion' '
	bench help -c >human &&
	grep -E \
	     -e "^[^.]+\.[^.]+$" \
	     -e "^[^.]+\.[^.]+\.[^.]+$" human |
	     sed -e "s/\*.*//" -e "s/<.*//" |
	     sort -u >human.munged &&

	bench help --config-for-completion >vars &&
	test_cmp human.munged vars
'

test_expect_success 'bench help --config-sections-for-completion' '
	bench help -c >human &&
	grep -E \
	     -e "^[^.]+\.[^.]+$" \
	     -e "^[^.]+\.[^.]+\.[^.]+$" human |
	     sed -e "s/\..*//" |
	     sort -u >human.munged &&

	bench help --config-sections-for-completion >sections &&
	test_cmp human.munged sections
'

test_section_spacing () {
	cat >expect &&
	"$@" >out &&
	grep -E "(^[^ ]|^$)" out >actual
}

test_section_spacing_trailer () {
	test_section_spacing "$@" &&
	test_expect_code 1 bench >out &&
	sed -n '/list available subcommands/,$p' <out >>expect
}


for cmd in bench "bench help"
do
	test_expect_success "'$cmd' section spacing" '
		test_section_spacing_trailer bench help <<-\EOF &&
		usage: bench [-v | --version] [-h | --help] [-C <path>] [-c <name>=<value>]

		These are common Git commands used in various situations:

		start a working area (see also: bench help tutorial)

		work on the current change (see also: bench help everyday)

		examine the history and state (see also: bench help revisions)

		grow, mark and tweak your common history

		collaborate (see also: bench help workflows)

		EOF
		test_cmp expect actual
	'
done

test_expect_success "'bench help -a' section spacing" '
	test_section_spacing \
		bench help -a --no-external-commands --no-aliases <<-\EOF &&
	See '\''bench help <command>'\'' to read about a specific subcommand

	Main Porcelain Commands

	Ancillary Commands / Manipulators

	Ancillary Commands / Interrogators

	Interacting with Others

	Low-level Commands / Manipulators

	Low-level Commands / Interrogators

	Low-level Commands / Syncing Repositories

	Low-level Commands / Internal Helpers

	User-facing repository, command and file interfaces

	Developer-facing file formats, protocols and other interfaces
	EOF
	test_cmp expect actual
'

test_expect_success "'bench help -g' section spacing" '
	test_section_spacing_trailer bench help -g <<-\EOF &&
	The Git concept guides are:

	EOF
	test_cmp expect actual
'

test_expect_success 'generate builtin list' '
	mkdir -p sub &&
	bench --list-cmds=builtins >builtins
'

while read builtin
do
	test_expect_success "$builtin can handle -h" '
		(
			GIT_CEILING_DIRECTORIES=$(pwd) &&
			export GIT_CEILING_DIRECTORIES &&
			test_expect_code 129 bench -C sub $builtin -h >output 2>err
		) &&
		test_must_be_empty err &&
		test_grep usage output
	'
done <builtins

test_done
