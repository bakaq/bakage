/* SPDX-License-Identifier: Unlicense */

%:- module(pkg, [pkg_install/1]).

:- use_module(library(os)).
:- use_module(library(pio)).
:- use_module(library(files)).
:- use_module(library(lists)).
:- use_module(library(charsio)).
:- use_module(library(format)).
:- use_module(library(debug)).

% Cleanly pass arguments to a script through environment variables

run_script_with_args(ScriptName, Args, Success) :-
    maplist(define_script_arg, Args),
    append(["sh scryer_libs/scripts/", ScriptName, ".sh"], Script),
    (
        shell(Script) ->
            Success = true
        ;   Success = false
    ),
    maplist(undefine_script_arg, Args).

run_script_with_args(ScriptName, Args, Result_Filename, Result, Success) :-
    run_script_with_args(ScriptName, Args, Success),
    ( 
        Success == true -> 
            result_from_file(Result_Filename, Result)
        ;   Result = failure
    ).

result_from_file(Result_Filename, Result) :-
    open(Result_Filename, read, Stream),
    read(Stream, result(Result)),
    close(Stream),
    delete_file(Result_Filename).

define_script_arg(Arg-Value) :- setenv(Arg, Value).
undefine_script_arg(Arg-_) :- unsetenv(Arg).

scryer_path(ScryerPath) :-
    (   getenv("SCRYER_PATH", ScryerPath) ->
        true
    ;   ScryerPath = "scryer_libs"
    ).

parse_manifest(Filename, Manifest) :-
    open(Filename, read, Stream),
    parse_manifest_(Stream, Manifest),
    close(Stream).

parse_manifest_(Stream, Manifest) :-
    read(Stream, Term),
    (   Term == end_of_file ->
        Manifest = []
    ;   Manifest = [Term|Ms],
        parse_manifest_(Stream, Ms)
    ).

user:term_expansion((:- use_module(pkg(Package))), UsePackage) :-
    atom_chars(Package, PackageChars),
    scryer_path(ScryerPath),
    append([ScryerPath, "/packages/", PackageChars], PackagePath),
    append([PackagePath, "/", "scryer-manifest.pl"], ManifestPath),
    parse_manifest(ManifestPath, Manifest),
    member(main_file(MainFile), Manifest),
    append([PackagePath, "/", MainFile], PackageMainFileChars),
    atom_chars(PackageMainFile, PackageMainFileChars),
    UsePackage = (
        :- use_module(PackageMainFile)
    ).

% This creates the directory structure we want
ensure_scryer_libs :-
    (   directory_exists("scryer_libs") ->
        true
    ;   make_directory_path("scryer_libs")
    ),
    (   directory_exists("scryer_libs/packages") ->
        true
    ;   make_directory_path("scryer_libs/packages")
    ),
    (   directory_exists("scryer_libs/scripts") ->
        true
    ;   make_directory_path("scryer_libs/scripts"),
        ensure_scripts
    ),
    (   directory_exists("scryer_libs/temp") ->
        true
    ;   make_directory_path("scryer_libs/temp")
    ).

% Installs helper scripts
ensure_scripts :-
    findall(ScriptName-ScriptString, script_string(ScriptName, ScriptString), Scripts),
    maplist(ensure_script, Scripts).

ensure_script(Name-String) :-
    append(["scryer_libs/scripts/", Name, ".sh"], Path),
    phrase_to_file(String, Path).

pkg_install(Results) :-
    parse_manifest("scryer-manifest.pl", Manifest),
    ensure_scryer_libs,
    setenv("SHELL", "/bin/sh"),
    setenv("GIT_ADVICE", "0"),
    (   file_exists("manifest-lock.pl") ->
        parse_manifest("manifest-lock.pl", LockFile),
        member(lock_dependencies(LockDeps),LockFile)
    ;   LockDeps = []
    ),
    (   member(dependencies(Deps), Manifest) ->
        plan(logical_plan(IPlan, LPlan), Deps, LockDeps)
    ;   true
    ),
    installation_execution(IPlan, InstallResults),
    lock_execution(LPlan, LockTerms, LockResult),
    materialize_lock_file(LockTerms),
    append([InstallResults, LockResult], Results).

materialize_lock_file(LockTerms) :-
    open('manifest-lock', write, Stream),
    write(Stream, '% WARNING: This file is auto-generated. Do NOT modify it manually.\n\n'),
    write_term(Stream, lock_dependencies(LockTerms), [double_quotes(true)]),
    write(Stream, '.\n'),
    close(Stream).

installation_execution([], []).
installation_execution([P|Ps], Results):-
    installation_execution(Ps, Result0),
    execution_step(P, Result),
    append([Result0, [Result]],Results).

lock_execution([], [], []).

lock_execution([P|Ps], LockTerms, Results):-
    lock_execution(Ps, LockTerms0, Results0),
    execution_lock_step(P, LockTerm, Result),
    append([Results0, [Result]],Results),
    append([LockTerms0, [LockTerm]], LockTerms).

execution_step(install(do_nothing(dependency(Name, DependencyTerm))), install(do_nothing(dependency(Name, DependencyTerm)))-success(true)) :-
    current_output(Out),
    phrase_to_stream(("Already installed: ", portray_clause_(dependency(Name, DependencyTerm))), Out).

execution_step(install(install_dependency(D)), Result) :-
    ensure_dependency(D, Sucess),
    Result = install(install_dependency(D))-sucess(Sucess).

execution_step(install(install_locked_dependency(D)), Result) :- execution_step(install(install_dependency(D)), Result).

execution_lock_step(lock(dependency(Name, git(Url,hash(Hash)))), dependency(Name, git(Url,hash(Hash))), lock(dependency(Name, git(Url,hash(Hash))))-success(true)) :- !.

execution_lock_step(lock(dependency(Name, path(Path))), dependency(Name, path(Path)), lock(dependency(Name, path(Path)))-success(true)) :- !.

execution_lock_step(lock(dependency(Name, git(Url))), LockedDependency, Result) :-
    ensure_lock(dependency(Name, git(Url)), Hash, Success),
    (
        Success == true ->
            LockedDependency = dependency(Name, git(Url, hash(Hash))),
            Result = lock(dependency(Name, git(Url)))-success(true)
        ;   
            LockedDependency = null,
            Result = lock(dependency(Name, git(Url)))-success(false)
    ).

execution_lock_step(lock(dependency(Name, git(Url, Opt))), LockedDependency, Result) :-
    ensure_lock(dependency(Name, git(Url, Opt)), Hash, Success),
    (
        Success == true ->
            LockedDependency = dependency(Name, git(Url, hash(Hash))),
            Result = lock(dependency(Name, git(Url, Opt)))-success(true)
        ;   
            LockedDependency = null,
            Result = lock(dependency(Name, git(Url, Opt)))-success(false)
    ).


lock_dependency_with_name([dependency(Name, X, _)|_], dependency(Name, _), dependency(Name, X)) :- !.

lock_dependency_with_name([_|Ls], dependency(Name, _), Dep) :-
    lock_dependency_with_name(Ls, dependency(Name, _), Dep).

plan(logical_plan(IPlan, LPlan), Ds, LockDeps) :-
    installation_plan(IPlan, Ds, LockDeps),
    lock_plan(LPlan, Ds).

installation_plan([], [], _).

installation_plan(Plan, [D|Ds], LockDeps) :-
    installation_plan(Plan0, Ds, LockDeps),
    install_step(Installation_Step, D, LockDeps),
    append([Plan0, [Installation_Step]], Plan).

lock_plan([], []).

lock_plan(Plan, [D|Ds]):-
    lock_plan(Plan0, Ds),
    append([Plan0, [lock(D)]], Plan).


install_step(Installation_Step, dependency(Name, DependencyTerm), LockDeps):-
    append(["scryer_libs/packages/", Name], DepRepo),
    (
    directory_exists(DepRepo) ->
        Installation_Step = install(do_nothing(dependency(Name, DependencyTerm)))
    ;   (
            lock_dependency_with_name(LockDeps, dependency(Name, DependencyTerm), D) ->
                Installation_Step = install(install_locked_dependency(D))
            ;   Installation_Step = install(install_dependency(dependency(Name, DependencyTerm)))
        )
    ).

ensure_lock(dependency(Name, _), Hash, Success) :-
    Arg = [
        "DEPENDENCY_NAME"-Name
    ],
    append(["scryer_libs/temp/lock_dependency_", Name], Result_Filename),
    run_script_with_args("lock_dependency", Arg, Result_Filename, Hash, Success).

ensure_dependency(dependency(Name, DependencyTerm), Success) :-
    write_term_to_chars(DependencyTerm, [quoted(true), double_quotes(true)], DependencyTermChars),
    CommonArgs = [
        "DEPENDENCY_NAME"-Name,
        "DEPENDENCY_TERM"-DependencyTermChars
    ],
    ensure_dependency_extra_args(DependencyTerm, ExtraArgs),
    append(CommonArgs, ExtraArgs, Args),
    run_script_with_args("ensure_dependency", Args, Success).

ensure_dependency_extra_args(git(Url), [
    "DEPENDENCY_KIND"-"git_default",
    "GIT_URL"-Url
]).
ensure_dependency_extra_args(git(Url,branch(Branch)), [
    "DEPENDENCY_KIND"-"git_branch",
    "GIT_URL"-Url,
    "GIT_BRANCH"-Branch
]).
ensure_dependency_extra_args(git(Url,tag(Tag)), [
    "DEPENDENCY_KIND"-"git_tag",
    "GIT_URL"-Url,
    "GIT_TAG"-Tag
]).
ensure_dependency_extra_args(git(Url,hash(Hash)), [
    "DEPENDENCY_KIND"-"git_hash",
    "GIT_URL"-Url,
    "GIT_HASH"-Hash
]).
ensure_dependency_extra_args(path(Path), [
    "DEPENDENCY_KIND"-"path",
    "DEPENDENCY_PATH"-Path
]).

% === Generated code start ===
script_string("ensure_dependency", "#!/bin/sh\nset -eu\n\necho \"Ensuring is installed: ${DEPENDENCY_TERM}\"\n\ncase \"${DEPENDENCY_KIND}\" in\n    git_default)\n        git clone \\\n            --quiet \\\n            --depth 1 \\\n            --single-branch \\\n            \"${GIT_URL}\" \\\n            scryer_libs/packages/${DEPENDENCY_NAME}\n        ;;\n    git_branch)\n        git clone \\\n            --quiet \\\n            --depth 1 \\\n            --single-branch \\\n            --branch \"${GIT_BRANCH}\" \\\n            \"${GIT_URL}\" \\\n            scryer_libs/packages/${DEPENDENCY_NAME}\n        ;;\n    git_tag)\n        git clone \\\n            --quiet \\\n            --depth 1 \\\n            --single-branch \\\n            --branch \"${GIT_TAG}\" \\\n            \"${GIT_URL}\" \\\n            scryer_libs/packages/${DEPENDENCY_NAME}\n        ;;\n    git_hash)\n        git clone \\\n            --quiet \\\n            --depth 1 \\\n            --single-branch \\\n            \"${GIT_URL}\" \\\n            scryer_libs/packages/${DEPENDENCY_NAME}\n        git -C scryer_libs/packages/${DEPENDENCY_NAME} fetch \\\n            --quiet \\\n            --depth 1 \\\n            origin \"${GIT_HASH}\"\n        git -C scryer_libs/packages/${DEPENDENCY_NAME} switch \\\n            --quiet \\\n            --detach \\\n            \"${GIT_HASH}\"\n        ;;\n    path)\n        ln -rsf \"${DEPENDENCY_PATH}\" \"scryer_libs/packages/${DEPENDENCY_NAME}\"\n        ;;\n    *)\n        echo \"Unknown dependency kind\"\n        exit 1\n        ;;\nesac\n").
script_string("lock_dependency", "#!/bin/sh\nset -eu\n\ncd scryer_libs/packages/${DEPENDENCY_NAME} && echo \"result(\\\"$(git rev-parse HEAD)\\\").\" > ../../temp/lock_dependency_${DEPENDENCY_NAME}").
% === Generated code end ===
