/* SPDX-License-Identifier: Unlicense */

:- module(bakage, [pkg_install/1]).

% ==========================
% === Compatibility zone ===
% ==========================

% Everything that is implementation specific, implementation defined, or otherwise not guaranteed
% by the base 13211-1 ISO standard with corrigenda should be encapsulated here so that we only
% have to look in one place when porting or making this more portable.

% Hard to shim

:- use_module(library(os), [argv/1, setenv/2, shell/1, unsetenv/1, getenv/2]).
:- use_module(library(files), [
    directory_exists/1, make_directory_path/1, directory_files/2, file_exists/1,
    delete_file/1, delete_directory/1, working_directory/2
]).
:- use_module(library(dcgs), [phrase/2, phrase/3, ... //0]). % 13211-3
:- use_module(library(charsio), [write_term_to_chars/3]).
:- use_module(library(iso_ext), [setup_call_cleanup/3, call_cleanup/2]).

% Easy to shim
:- use_module(library(lists), [
    length/2, maplist/1, member/2, append/2, maplist/2, append/3, memberchk/2
]).
:- use_module(library(pio), [phrase_to_file/2, phrase_to_stream/2]).
:- use_module(library(dif), [dif/2]). % With dif_si/2, though that may lose some functionality
:- use_module(library(reif), [if_/3, (;)/3, memberd_t/3, (=)/3]).
:- use_module(library(format), [portray_clause/1, portray_clause_//1]).

user:term_expansion((:- use_module(pkg(Package))), (:- use_module(PackageMainFile))) :-
    package_main_file(Package, PackageMainFile).

% =================================
% === End of compatibility zone ===
% =================================


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

define_script_arg(Arg-Value) :- setenv(Arg, Value).
undefine_script_arg(Arg-_) :- unsetenv(Arg).

% join_sep_split/3: Monotonic join and split by separator.
% Implementation by @bakaq from https://github.com/mthom/scryer-prolog/discussions/3121
%
% True when `Joined` is a list consisting of all the lists in `Segments`
% separated by `Separator`, and `Separator` doesn't appear in any of the
% lists in `Segments`. Can be used as both a split and a join depending
% on the mode.
join_sep_split(Joined, Separator, Segments) :-
    join_sep_split_(Separator, Joined, Segments).

% The empty separator case is just append/2
join_sep_split_([], Joined, Segments) :-
    append(Segments, Joined).
join_sep_split_([S|Ss], Joined, Segments) :-
    join_sep_split(Joined, [], [S|Ss], Segments, []).

% Stuff like this that needs 2 list differences is hard to encode
% in a DCG in my experience.
join_sep_split([], [], _, [], []).
join_sep_split([L0|LT0], Ls, Sep, [Seg|Segs0], Segs) :-
    Ls0 = [L0|LT0],
    next_segment(Ls0, Seg, Sep, Ls1, Reason),
    join_sep_split_(Ls1, Ls, Sep, Segs0, Segs, Reason).

join_sep_split_([], [], _, Segs0, Segs, Reason) :-
    reason_segs(Reason, Segs0, Segs).
join_sep_split_([L0|LT0], Ls, Sep, Segs0, Segs, _) :-
    join_sep_split([L0|LT0], Ls, Sep, Segs0, Segs).

reason_segs(sep, [[]|Segs], Segs).
reason_segs(end, Segs, Segs).

next_segment([], [], _, [], end).
next_segment([L0|Ls0], Seg, Sep, Ls, Reason) :-
    if_(
        starts_with_t(Sep, [L0|Ls0], Ls1),
        (Ls = Ls1, Seg = [], Reason = sep),
        (Seg = [L0|Seg1], next_segment(Ls0, Seg1, Sep, Ls, Reason))
    ).

starts_with_t([], Ls, Ls, true).
starts_with_t([S|Ss], Ls0, Ls, T) :-
    starts_with_t_(Ls0, Ls, S, Ss, T).

starts_with_t_([], _, _, _, false).
starts_with_t_([L|Ls0], Ls, S, Ss, T) :-
    if_(
        S = L,
        starts_with_t(Ss, Ls0, Ls, T),
        T = false
    ).

find_project_root(Root) :-
    working_directory(CWD, CWD),
    find_project_root_from(CWD, Root).

find_project_root_from(Dir, Root) :-
    append(Dir, "/scryer-manifest.pl", ManifestPath),
    (   file_exists(ManifestPath) ->
        Root = Dir
    ;   join_sep_split(Dir, "/", Segments),
        append(ParentSegments, [_LastSegment], Segments),
        ParentSegments \= [],
        join_sep_split(ParentDir, "/", ParentSegments),
        find_project_root_from(ParentDir, Root)
    ).

scryer_path(ScryerPath) :-
    (   getenv("SCRYER_PATH", EnvPath) ->
        ScryerPath = EnvPath
    ;   find_project_root(RootChars),
        append([RootChars, "/scryer_libs"], ScryerPath)
    ).

% Get the current project's manifest (if it exists)
current_project_manifest(Manifest) :-
    find_project_root(Root),
    append([Root, "/scryer-manifest.pl"], ManifestPath),
    file_exists(ManifestPath),
    parse_manifest(ManifestPath, Manifest).

% Extract scryer_path/1 terms from manifest (list of manifest file paths)
manifest_scryer_paths(Manifest, ManifestPaths) :-
    member(scryer_path(ManifestPaths), Manifest),
    ManifestPaths = [_|_].

% Given a manifest file path, derive where its packages are located
manifest_path_to_scryer_libs(ManifestPathChars, ScryerLibsPath) :-
    join_sep_split(ManifestPathChars, "/", Segments),
    append(DirSegments, [_ManifestFile], Segments),
    join_sep_split(DirChars, "/", DirSegments),
    append([DirChars, "/scryer_libs"], ScryerLibsPath).

% Generate scryer path candidates via backtracking
scryer_path_candidate(Path) :-
    getenv("SCRYER_PATH", Path).
scryer_path_candidate(ScryerLibsPath) :-
    current_project_manifest(Manifest),
    manifest_scryer_paths(Manifest, ManifestPaths),
    member(ManifestPath, ManifestPaths),
    manifest_path_to_scryer_libs(ManifestPath, ScryerLibsPath).
scryer_path_candidate(Path) :-
    find_project_root(RootChars),
    append([RootChars, "/scryer_libs"], Path).

% Collect all scryer path candidates into a list
all_scryer_path_candidates(Paths) :-
    findall(Path, scryer_path_candidate(Path), Paths).

% the message sent to the user when a dependency is malformed
user_message_malformed_dependency(D, Error):-
    current_output(Out),
    phrase_to_stream((portray_clause_(D), "is malformed: ", Error, "\n"), Out).

% A prolog file knowledge base represented as a list of terms
prolog_kb_list(Stream) --> {read(Stream, Term), dif(Term, end_of_file)}, [Term], prolog_kb_list(Stream).
prolog_kb_list(Stream) --> {read(Stream, Term), Term == end_of_file}, [].

parse_manifest(Filename, Manifest) :-
    setup_call_cleanup(
        open(Filename, read, Stream),
        catch(once(phrase(prolog_kb_list(Stream), Manifest)), error(E, I), throw(error_formating_of_manifest(E, I))),
        close(Stream)
    ).

package_main_file(Package, PackageMainFile) :-
    atom_chars(Package, PackageChars),
    all_scryer_path_candidates(CandidatePaths),
    member(ScryerPath, CandidatePaths),
    append([ScryerPath, "/packages/", PackageChars], PackagePath),
    append([PackagePath, "/", "scryer-manifest.pl"], ManifestPath),
    file_exists(ManifestPath),
    parse_manifest(ManifestPath, Manifest),
    member(main_file(MainFile), Manifest),
    append([PackagePath, "/", MainFile], PackageMainFileChars),
    atom_chars(PackageMainFile, PackageMainFileChars).

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


% Predicate to install the dependencies
pkg_install(Report) :-
        parse_manifest("scryer-manifest.pl", Manifest),
        ensure_scryer_libs,
        setenv("SHELL", "/bin/sh"),
        setenv("GIT_ADVICE", "0"),
        directory_files("scryer_libs/packages", Installed_Packages),
        if_(valid_manifest_t(Manifest, Validation_Report),
            (member(dependencies(Deps), Manifest) ->
                call_cleanup(
                    (
                    logical_plan(Plan, Deps, Installed_Packages),
                    installation_execution(Plan, Installation_Report),
                    append(Validation_Report, Installation_Report, Report)
                    ),
                    delete_directory("scryer_libs/temp")
                ) ; Report = Validation_Report
            ),
            Report = Validation_Report
        ).

% A logical plan to install the dependencies
logical_plan(Plan, Ds, Installed_Packages) :-
    phrase(fetch_plan(Ds, Installed_Packages), Plan).

% A logical plan to fetch the dependencies
fetch_plan([], _) --> [].
fetch_plan([D|Ds], Installed_Packages) -->
    {fetch_step(D, Installation_Step, Installed_Packages)},
    [Installation_Step],
    fetch_plan(Ds, Installed_Packages).


% A step of a logical plan to fetch the dependencies
fetch_step(dependency(Name, DependencyTerm), Step, Installed_Packages) :-
    if_(memberd_t(Name, Installed_Packages),
        Step = do_nothing(dependency(Name, DependencyTerm)),
        Step = install_dependency(dependency(Name, DependencyTerm))
    ).

% Execute the physical installation of the dependencies
installation_execution(Plan, Results):-
    ensure_dependencies(Plan, Success),
    if_(Success = false,
        phrase(fail_installation(Plan), Results),
        true
    ),
    parse_install_report(Result_Report),
    phrase(installation_report(Plan, Result_Report), Results).

% All dependency installation failed
fail_installation([]) --> [].
fail_installation([P|Ps]) --> [P-error("installation script failed")], fail_installation(Ps).


% Parse the report of the installation of the dependencies
parse_install_report(Result_List) :-
    setup_call_cleanup(
        open("scryer_libs/temp/install_resp.pl", read, Stream),
        once(phrase(prolog_kb_list(Stream), Result_List)),
        (
            close(Stream),
            ( file_exists("scryer_libs/temp/install_resp.pl")->
                delete_file("scryer_libs/temp/install_resp.pl")
            ; true
            )
        )
    ).

% The installation report of the dependencies
installation_report([], _) --> [].
installation_report([P|Ps], Result_Report) -->
    { report_installation_step(P, Result_Report, R) },
    [R],
    installation_report(Ps, Result_Report).

% The result of a logical step
report_installation_step(do_nothing(dependency(Name, DependencyTerm)), _, do_nothing(dependency(Name, DependencyTerm))-success).


report_installation_step(install_dependency(dependency(Name, DependencyTerm)), ResultMessages, install_dependency(dependency(Name, DependencyTerm))-Message):-
    memberchk(result(Name, Message), ResultMessages).

% Execute the logical plan
ensure_dependencies(Logical_Plan, Success) :-
    phrase(physical_plan(Logical_Plan), Physical_Plan),
    Args = [
        "DEPENDENCIES_STRING"-Physical_Plan
    ],
    run_script_with_args("ensure_dependencies", Args, Success).


% Create a physical plan in shell script
physical_plan([]) --> [].
physical_plan([P|Ps]) --> physical_plan_([P|Ps]).

physical_plan_([P]) --> {
    physical_plan_step(P, El)
    },
    El.

physical_plan_([P|Ps]) --> {
    physical_plan_step(P, El)
    },
    El,
    "|",
    physical_plan_(Ps).

% Create a step for the shell script physical plan
physical_plan_step(do_nothing(dependency(Name, D)) , El) :-
    write_term_to_chars(D, [quoted(true), double_quotes(true)], DependencyTermChars),
    append(["dependency_term=", DependencyTermChars, ";dependency_name=", Name, ";dependency_kind=do_nothing"], El).

physical_plan_step(install_dependency(dependency(Name, git(Url))) ,El):-
    write_term_to_chars(git(Url), [quoted(true), double_quotes(true)], DependencyTermChars),
    append(["dependency_term=", DependencyTermChars, ";dependency_name=", Name, ";dependency_kind=git_default;git_url=", Url], El).

physical_plan_step(install_dependency(dependency(Name, git(Url,branch(Branch)))) ,El):-
    write_term_to_chars(git(Url,branch(Branch)), [quoted(true), double_quotes(true)], DependencyTermChars),
    append(["dependency_term=", DependencyTermChars, ";dependency_name=", Name, ";dependency_kind=git_branch;git_url=", Url, ";git_branch=", Branch], El).

physical_plan_step(install_dependency(dependency(Name, git(Url,tag(Tag)))) ,El):-
    write_term_to_chars(git(Url,tag(Tag)), [quoted(true), double_quotes(true)], DependencyTermChars),
    append(["dependency_term=", DependencyTermChars, ";dependency_name=", Name, ";dependency_kind=git_tag;git_url=", Url, ";git_tag=", Tag], El).

physical_plan_step(install_dependency(dependency(Name, git(Url,hash(Hash)))) ,El):-
    write_term_to_chars(git(Url,hash(Hash)), [quoted(true), double_quotes(true)], DependencyTermChars),
    append(["dependency_term=", DependencyTermChars, ";dependency_name=", Name, ";dependency_kind=git_hash;git_url=", Url, ";git_hash=", Hash], El).

physical_plan_step(install_dependency(dependency(Name, path(Path))) ,El):-
    write_term_to_chars(path(Path), [quoted(true), double_quotes(true)], DependencyTermChars),
    append(["dependency_term=", DependencyTermChars, ";dependency_name=", Name, ";dependency_kind=path;dependency_path=", Path], El).
