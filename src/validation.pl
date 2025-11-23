:- use_module(library(lists)).
:- use_module(library(reif)).
:- use_module(library(debug)).
:- use_module(library(files)).

is_list_t(Ls, T) :-
    match(Ls, [
        arm(ground([]), (T = true)),
        arm(composite([any | bind(Ls1)]), is_list_t(Ls1, T)),
        arm(any, (T = false))
    ]).


file_exists_t(P, true):- file_exists(P),!.
file_exists_t(_, false).

license_t_(license(name(N)), T):- is_list_t(N, T).

license_t_(license(name(N), path(P)), T) :-
    call((is_list_t(N), is_list_t(P)), T).

license_valid_path_t([], Result1, Result1).
license_valid_path_t([_,_|_], Result1, Result1).
license_valid_path_t([license(name(_))], Result1, Result1).
license_valid_path_t([license(name(_), path(P))], Result1, Result2):-
    if_(file_exists_t(P),
        (Result2 = Result1),
        (
          Err = "the path of the license is not valid",
          Result2 = error(Err),
          user_message_invalid_manifest(Err)
        )
    ).

license_t(X, T) :-
    match(X, [
        arm(composite(license(bind(N))), (license_t_(license(N), T))),
        arm(composite(license(bind(N), bind(P))), (license_t_(license(N, P), T))),
        arm(any, (T = false))
    ]).

name_t(X, T) :-
    match(X, [
        arm(composite(name(bind(N))), (is_list_t(N, T))),
        arm(any, (T = false))
    ]).

dependencies_t(X, T) :-
    match(X, [
        arm(composite(dependencies(bind(N))), (is_list_t(N, T))),
        arm(any, (T = false))
    ]).

main_file_t(X, T) :-
    match(X, [
        arm(composite(main_file(bind(N))), (is_list_t(N, T))),
        arm(any, (T = false))
    ]).

pattern_in_list([], _) --> [].

pattern_in_list([L|Ls], Pattern_t) -->
    {
        if_(call(Pattern_t, L),
            Match = [L],
            Match = []
        )
    },
    Match,
    pattern_in_list(Ls, Pattern_t).

% A valid manifest
valid_manifest_t(Manifest, Report, Valid) :-
    has_valid_name(Manifest, ValidName),
    has_valid_optional_main_file(Manifest, ValidMainFile),
    has_license(Manifest, ValidLicense),
    has_optional_dependencies(Manifest, ValidDendencies),
    if_((ValidName=success, ValidMainFile=success, ValidLicense=success, ValidDendencies=success),
        if_(memberd_t(dependencies(Deps), Manifest),
            (
                phrase(valid_dependencies(Deps), DepsReport),
                if_(all_dependencies_valid_t(DepsReport),
                    (
                        Report = [validate_manifest-success],
                        Valid=true
                    ),
                    (
                        Report = DepsReport,
                        Valid=false
                    )
                )
            ),
            (
                Report = [validate_manifest-success],
                Valid = true
            )

        ),
        (
            Report = [
                validate_manifest_name-ValidName,
                validate_manifest_main_file-ValidMainFile,
                validate_manifest_license-ValidLicense,
                validate_dependencies-ValidDendencies
                ],
            Valid = false
        )

    ).

% the message sent to the user when a dependency is malformed
user_message_malformed_dependency(D, Error):-
    current_output(Out),
    phrase_to_stream((portray_clause_(D), "is malformed: ", Error, "\n"), Out).

% the message sent to the user when there is a validation error
user_message_invalid_manifest(Error):-
    current_output(Out),
    phrase_to_stream(("The installation failed; cause:\n\t", Error, "\n"), Out).

% Is valid when there is 0 instance and the field is optional
has_a_field([], _, _, true, success).

% Is not valid when there is 0 instance and the field is not optional
has_a_field([], FieldName, PredicateForm, false, error(Es)):-
    phrase(format_("the '~s' of the package is not defined or does not have the a predicate of the form '~s'", [FieldName, PredicateForm]), Es),
    user_message_invalid_manifest(Es).

% Is valid when there is one instance of the field and the field value has the correct type
has_a_field([_], _, _, _, success).

% Is not valid when there are multiple instances of the field
has_a_field([_,_|_], FieldName, _, _, error(Es)):-
     phrase(format_("the package has multiple '~s'", [FieldName]), Es),
     user_message_invalid_manifest(Es).

has_valid_name(Manifest, Result):-
    phrase(pattern_in_list(Manifest, name_t), S),
    has_a_field(S, "name", "name(N)", false, Result).

has_valid_optional_main_file(Manifest, Result) :-
    phrase(pattern_in_list(Manifest, main_file_t), S),
    has_a_field(S, "main_file", "main_file(N)", true, Result).

has_license(Manifest, Result) :-
    phrase(pattern_in_list(Manifest, license_t), S),
    has_a_field(S, "license", "license(name(N));license(name(N), path(P))", false, Result1),
    license_valid_path_t(S, Result1, Result).

has_optional_dependencies(Manifest, Result):-
    phrase(pattern_in_list(Manifest, dependencies_t), S),
    has_a_field(S, "dependencies", "dependencies(D)", true, Result).

% A valid dependency
valid_dependencies([]) --> [].

valid_dependencies([dependency(Name, path(Path))| Ds]) --> {
    if_(
        (memberd_t(';', Name)
        ; memberd_t('|', Name)
        ; memberd_t(';', Path)
        ; memberd_t('|', Path)
        ),
        (
            Error = "the name and the path of the dependency should not contain an \";\" or an \"|\" caracter",
            M = validate_dependency(dependency(Name, path(Path)))-error(Error),
            user_message_malformed_dependency(dependency(Name, path(Path)), Error)
        ),
        M = validate_dependency(dependency(Name, path(Path)))-success
    )
    },
    [M],
    valid_dependencies(Ds).

valid_dependencies([dependency(Name, git(Url))| Ds]) --> {
    if_(
        (memberd_t(';', Name)
            ; memberd_t('|', Name)
            ; memberd_t(';', Url)
            ; memberd_t('|', Url)
        ),
        (
            Error = "the name of the dependency and the url should not contain an \";\" or an \"|\" caracter",
            M = validate_dependency(dependency(Name, git(Url)))-error(Error),
            user_message_malformed_dependency(dependency(Name, git(Url)), Error)
        ),
         M = validate_dependency(dependency(Name, git(Url)))-success
    )
    },
    [M],
    valid_dependencies(Ds).

valid_dependencies([dependency(Name, git(Url, branch(Branch)))| Ds]) --> {
    if_(
        (memberd_t(';', Name)
        ; memberd_t('|', Name)
        ; memberd_t(';', Url)
        ; memberd_t('|', Url)
        ; memberd_t(';', Branch)
        ; memberd_t('|', Branch)),
        (
            Error = "the name, the url and the branch of dependency should not contain an \";\" or an \"|\" caracter",
            M = validate_dependency(dependency(Name, git(Url, branch(Branch))))-error(Error),
            user_message_malformed_dependency(dependency(Name, git(Url, branch(Branch))), Error)
        ),(
            M = validate_dependency(dependency(Name, git(Url, branch(Branch))))-success
        )
    )
    },
    [M],
    valid_dependencies(Ds).

valid_dependencies([dependency(Name, git(Url, tag(Tag)))|Ds]) --> {
    if_(
        (memberd_t(';', Name)
        ; memberd_t('|', Name)
        ; memberd_t(';', Url)
        ; memberd_t('|', Url)
        ; memberd_t(';', Tag)
        ; memberd_t('|', Tag)),
        (
            Error = "the name, the url and the tag of dependency should not contain an \";\" or an \"|\" caracter",
            M = validate_dependency(dependency(Name, git(Url, tag(Tag))))-error(Error),
            user_message_malformed_dependency(dependency(Name, git(Url, tag(Tag))), Error)
        ),
        M = validate_dependency(dependency(Name, git(Url, tag(Tag))))-success
    )
    },
    [M],
    valid_dependencies(Ds).

valid_dependencies([dependency(Name, git(Url, hash(Hash)))|Ds]) --> {
    if_(
        (memberd_t(';', Name)
        ; memberd_t('|', Name)
        ; memberd_t(';', Url)
        ; memberd_t('|', Url)
        ; memberd_t(';', Hash)
        ; memberd_t('|', Hash)),
        (
            Error = "the name, the url and the hash of dependency should not contain an \";\" or an \"|\" caracter",
            M = validate_dependency(dependency(Name, git(Url, hash(Hash))))-error(Error),
            user_message_malformed_dependency(dependency(Name, git(Url, hash(Hash))), Error)
        ),
        M = validate_dependency(dependency(Name, git(Url, hash(Hash))))-success
    )
    },
    [M],
    valid_dependencies(Ds).

all_dependencies_valid_t([], true).
all_dependencies_valid_t([validate_dependency(_)-success| Vs], T) :-  all_dependencies_valid_t(Vs, T).
all_dependencies_valid_t([validate_dependency(_)-error(_)| _], false).
