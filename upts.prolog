%% -*- mode: prolog; coding: utf-8 -*-

%%Travail realise par Jaydan ALADRO et Karim BOUMGHAR.
%%Nous sommes extremement decu de ne pas avoir pu terminer ce travail tres dur.

%% GNU Prolog défini `new_atom`, mais SWI Prolog l'appelle `gensym`.
genatom(X, A) :-
    (predicate_property(new_atom/2, built_in);    % Older GNU Prolog
     predicate_property(new_atom(_,_), built_in)) % Newer GNU Prolog
    -> new_atom(X, A);
    gensym(X, A).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Description de la syntaxe des termes %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% wf(+E)
%% Vérifie que E est une expression syntaxiquement correcte.
%% Cette règle est inutile en soit, elle ne sert qu'à documenter pour
%% vous la forme des termes du langage μPTS.

%% D'abord les termes du langage interne.
wf(X) :- identifier(X); integer(X); float(X).       %Une variable ou un nombre.
wf(fun(X, T, E)) :- identifier(X), wf(T), wf(E).    %Une fonction.
wf(app(E1, E2)) :- wf(E1), wf(E2).                  %Un appel de fonction.
wf(arw(X, T1, T2)) :- identifier(X), wf(T1), wf(T2). %Le type d'une fonction.
wf(let(X, T, E1, E2)) :- identifier(X), wf(T), wf(E1), wf(E2). %Def locale.

%% Puis les éléments additionnels acceptés dans le langage surface.
wf(forall(X, T, B)) :- identifier(X), wf(T), wf(B). %Type d'une fonc. implicite
wf(fun(X, B)) :- identifier(X), wf(B).
wf(let(X, E1, E2)) :- identifier(X), wf(E1), wf(E2).
wf(let(Decls, E)) :- wf_decls(Decls), wf(E).
wf((T1 -> T2)) :- wf(T1), wf(T2).
wf(forall(X, B)) :- (identifier(X); wf_ids(X)), wf(B).
wf((E : T)) :- wf(E), wf(T).
wf(E) :- E =.. [Head|Tail], identifier(Head), wf_exps(Tail).
wf(X) :- var(X).    %Une métavariable, utilisée pendant l'inférence de type.

%% identifier(+X)
%% Vérifie que X est un identificateur valide.
identifier(X) :- atom(X),
                 \+ member(X, [fun, app, arw, forall, (->), (:), let, [], (.)]).

wf_exps([]).
wf_exps([E|Es]) :- wf(E), wf_exps(Es).
wf_ids([]).
wf_ids([X|Xs]) :- identifier(X), wf_ids(Xs).
wf_decls([]).
wf_decls([X = E|Decls]) :-
    wf_decls(Decls), wf(E),
    (X = (X1 : T) -> wf(T), X1 =.. Ids, wf_ids(Ids);
     X =.. [F|Args], identifier(F), wf_args(Args)).
wf_args([]).
wf_args([X:T|Args]) :- wf_args(Args), identifier(X), wf(T).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Manipulation du langage interne %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% Occasionnellement pendant l'inférence de types, il se peut qu'une
%% métavariable apparaisse dans un terme du langage interne.  Donc les
%% prédicats ci-dessous font souvent attention à tester le cas `var(MV)`
%% (accompagné d'un `cut`) pour veiller à ne pas instancier cette
%% métavariable par inadvertance, parce que cela mène sinon très vite à des
%% boucles sans fin difficiles à déboguer.

%% subst(+Env, +X, +V, +Ei, -Eo)
%% Remplace X par V dans Ei.  V et Ei sont des expressions du langage interne.
%% Les variables qui peuvent apparaître libres dans V (et peuvent aussi
%% apparaître dans Ei) doivent toutes être incluses dans l'environnement Env.
%% Cette fonction évite la capture de nom, e.g.
%%
%%     subst(Env, x, y, fun(y,int,x+y), R)
%%
%% ne doit pas renvoyer `R = fun(y,int,y+y)` mais `R = fun(y1,int,y+y1)`.
subst(_, _, _, MV, Eo) :-
    %% Si MV est un terme non-instancié (i.e. une métavariable), la substitution
    %% ne peut pas encore se faire.  Dans certains cas, on pourrait renvoyer
    %% app(fun(X,Y),V), mais en général c'est problématique.
    %% Donc on impose ici la contrainte que les metavars ne peuvent pas
    %% faire référence à X.
    %% Le faire vraiment correctement est plus difficile.
    var(MV), !, Eo = MV.
subst(_, X, V, X, V).
subst(_, _, _, E, E) :- identifier(E); integer(E).
subst(Env, X, V, fun(Y, Ti, Bi), fun(Y1, To, Bo)) :-
    subst(Env, X, V, Ti, To),
    (X = Y ->
         %% Si X est égal à Y, X est caché, donc aucune substitution n'a lieu!
         Y1 = Y, Bo = Bi;
     (member((Y : _), Env) ->
          %% Si Y apparait dans Env, il peut apparaître dans V, donc on doit
          %% le renommer pour éviter une possible capture.
          genatom(Y, Y1),
          subst([], Y, Y1, Bi, Bi1);
      %% Cas "normal" où il n'y a pas de conflit de nom.
      Y1 = Y, Bi1 = Bi),
     %% Applique la substitution sur le corps de la fonction.
     subst(Env, X, V, Bi1, Bo)).
subst(Env, X, V, arw(Y, Ti, Bi), arw(Y1, To, Bo)) :-
    subst(Env, X, V, fun(Y, Ti, Bi), fun(Y1, To, Bo)).
subst(Env, X, V, forall(Y, Ti, Bi), forall(Y1, To, Bo)) :-
    subst(Env, X, V, fun(Y, Ti, Bi), fun(Y1, To, Bo)).
subst(Env, X, V, app(E1i, E2i), app(E1o, E2o)) :-
    subst(Env, X, V, E1i, E1o), subst(Env, X, V, E2i, E2o).


%% apply(+Env, +F, +Arg, -E)
%% Les règles d'évaluations primitives.  Env donne le types des variables
%% libres qui peuvent apparaître.
apply(Env, fun(X, _, B), Arg, E) :- \+ var(B), subst(Env, X, Arg, B, E).
apply(_,   app(+, N1), N2, N) :- integer(N1), integer(N2), N is N1 + N2.
apply(_,   app(-, N1), N2, N) :- integer(N1), integer(N2), N is N1 - N2.


%% normalize(+Env, +Ei, -Eo)
%% Applique toutes les réductions possibles sur Ei et tous ses sous-termes.
%% Utilisé pour tester si deux types sont équivalents.
normalize(_, MV, Eo) :- var(MV), !, Eo = MV.
normalize(_, V, V) :- (integer(V); float(V); identifier(V)).
normalize(Env, fun(X, T, B), fun(X, Tn, Bn)) :-
    normalize([X:T|Env], T, Tn), normalize([X:T|Env], B, Bn).
normalize(Env, arw(X, T, B), arw(X, Tn, Bn)) :-
    normalize([X:T|Env], T, Tn), normalize([X:T|Env], B, Bn).
normalize(Env, forall(X, T, B), forall(X, Tn, Bn)) :-
    normalize([X:T|Env], T, Tn), normalize([X:T|Env], B, Bn).
normalize(Env, app(E1, E2), En) :-
    normalize(Env, E1, E1n),
    normalize(Env, E2, E2n),
    (apply(Env, E1n, E2n, E) ->
         normalize(Env, E, En);
     En = app(E1n, E2n)).

%% equal(+Env, +T1, +T2)
%% Vérifie que deux expressions sont égales.
%% Utilisé pour vérifier l'égalité des types au niveau du langage interne, où
%% `forall` and `arw` sont équivalents.
equal(_, E, E).
equal(Env, forall(X1, T1, E1), E2) :- equal(Env, arw(X1, T1, E1), E2).
equal(Env, E2, forall(X1, T1, E1)) :- equal(Env, E2, arw(X1, T1, E1)).
equal(Env, fun(X1, T1, E1), fun(X2, T2, E2)) :-
    equal(Env, T1, T2),
    Env1 = [X1:T1|Env],
    (X1 = X2 ->
         E3 = E2;
     %% Si X1 et X2 sont différents, renomme X2 dans E2!
     subst(Env1, X2, X1, E2, E3)),
    equal(Env1, E1, E3).
equal(Env, arw(X1, T1, E1), arw(X2, T2, E2)) :-
    equal(Env, fun(X1, T1, E1), fun(X2, T2, E2)).
equal(Env, E1, E2) :-
    normalize(Env, E1, E1n),
    normalize(Env, E2, E2n),
    ((E1 = E1n, E2 = E2n) ->
         %% There was nothing to normalize :-(
         fail;
     equal(Env, E1n, E2n) -> true).
        

%% verify(+Env, +E, +T)
%% Vérifie que E a type T dans le contexte Env.
%% E est une expression du langage interne (i.e. déjà élaborée).
%% Elle ne devrait pas contenir de métavariables.
verify(Env, E, T) :-
    verify1(Env, E, T1) ->
        (equal(Env, T, T1) -> true;
         write(user_error, not_equal(T, T1)), nl(user_error), fail);
    write(user_error, verify_failure(E)), nl(user_error), fail.

%% verify1(+Env, +E, -T)
%% Calcule le type de E dans Env.
verify1(_, MV, _) :- var(MV), !, fail.
verify1(_, N, int) :- integer(N).
verify1(_, N, float) :- float(N).
verify1(Env, X, T) :-
    %% `member(X:T, Env)` risquerait de trouver dans Env un autre X que le
    %% plus proche, au cas où il y a plusieurs X dans l'environnement.
    atom(X), (member(X:T1, Env) -> T = T1; fail).
verify1(Env, fun(X, T1, E), forall(X, T1, T2)) :-
    verify(Env, T1, type),
    verify1([X:T1|Env], E, T2).
verify1(Env, app(F, A), T2) :-
    verify(Env, F, arw(X, T1, T3)),
    verify(Env, A, T1),
    subst(Env, X, A, T3, T2).
verify1(Env, arw(X, T1, T2), type) :-
    verify(Env, T1, type), verify([X:T1|Env], T2, type).
verify1(Env, forall(X, T1, T2), T) :- verify1(Env, arw(X, T1, T2), T).
verify1(Env, let(X, T, E1, E2), Tret) :-
    verify(Env, T, type),
    Env1 = [X:T|Env],
    verify(Env1, E1, T),
    verify1(Env1, E2, Tret).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Élaboration du langage surface vers le langage interne %%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


%% expand(+Ei, -Eo)
%% Remplace un élement de sucre syntaxique dans Ei, donnant Eo.
%% Ne renvoie jamais un Eo égal à Ei.
expand(MV, _) :- var(MV), !, fail.
expand((T1 -> T2), arw(X, T1, T2)) :- genatom('dummy_', X).
%% !!!À COMPLÉTER!!!

%%Expansion du forall ayant un argument implicite
expand(forall(X, E2), forall(X, _, E2)).
%%Expansion du forall imbrique
expand(forall(X, E1, E2), forall(X, E1, Eo)) :- expand(E2, Eo).
expand(forall(X,E1),Eo) :- X = [Head|Tail], forcurr(Head,Tail,E1,Eo).

%%Expansion des appel de fonctions imbrique
expand(Ei, Eo) :- Ei =.. [Head, Head2|Tail],
                  identifier(Head),
                  appcurr(Head, [Head2|Tail], Eo).

forcurr(X, [], E1, forall(X,E1)).
forcurr(X, [T|Ts], E1, forall(X,Ef)) :- forcurr(T,Ts,E1,Ef).
                 
appcurr(X, [], X).
appcurr(E, [Ei|Eis], Eo) :- appcurr(app(E, Ei), Eis, Eo).

%%expand(let(Decls,Ei), Eo) :- Decls = [Head|Tail]
%%                            letcurr(Ei, Head, [Tail], Eo).


%%letcurr(Ei, (X = E), [], Eo) :- letarg(Ei, X, E, Eo).
%%letcurr(Ei, (X = E), [Head|Tail], Eo) :- letcurr(Ei, Head, [Tail], Eo).

%%letcurr(Ei, (X : T = E), [], fun()) :- letarg(Ei, X, Eo)
%%letcurr(Ei, (X : T = E), [Head|Tail], Eo) :-

%%letarg(Ei, X, E , let(Head, Eo, Ei)) :- X=..[Head, Head2|Tail],
%%                                    letarg(Ei, [Head2|Tail], E , Eo).
%%letarg(Ei, X:T, E ,fun(X, T, E)).
%%letarg(Ei, [X:T|Tail], E, fun(X, T, Eo)) :- letarg(Ei, Tail, E, Eo).




%% coerce(+Env, +E1, +T1, +T2, -E2)
%% Transforme l'expression E1 (qui a type T1) en une expression E2 de type T2.
coerce(Env, E, T1, T2, E) :-
    T1 = T2;
    normalize(Env, T1, T1n),
    normalize(Env, T2, T2n),
    T1n = T2n.        %T1 = T2: rien à faire!
%% !!!À COMPLÉTER!!!
%%Regle de coercion du passage de int vers float
coerce(Env, E, T1, T2, app(int_to_float, E)) :- normalize(Env, T1, int),
                                                normalize(Env, T2, float).

%%Regle de coercion du passage de int vers bool
coerce(Env, E, T1, T2, app(int_to_bool, E)) :- normalize(Env, T1, int),
                                               normalize(Env, T2, bool).

%%Regle de coercion d'un forall()
coerce(Env, E, T1, T2, app(E, V)) :- normalize(Env, T1, forall(X,_, E3)), 
                                     subst(Env, X, V, E3, To), 
                                %%V sera trouver grace au equal
                                %%Mais si nous avons un forall imbrique,
                                %%nous appelons recursivement coerce pour
                                %%deconstruire et trouver notre V,
%%Nous sommes conscient qu'il y a un probleme dans la recursion de notre coerce
%%Notre T2 va toujours garder le meme type que notre E2 dans infer de app.
                                     (coerce(Env, E, To, T2, Too);
                                                    equal(Env, T2, Too)).


                                                

%% lookup(+Env,+X,-T)
%% Prend un environnement, une variable et retourne le type (s'il existe).
lookup([],_,_) :- false.
lookup([Xi:Ti|Envi],X,T) :- (X = Xi -> T = Ti; lookup(Envi,X,T)).


%% infer(+Env, +Ei, -Eo, -T)
%% Élabore Ei (dans un contexte Env) en Eo et infère son type T.
infer(_, MV, MV, _) :- var(MV), !.            %Une expression encore inconnue.
infer(Env, Ei, Eo, T) :- 
                        expand(Ei, Ei1),
                        infer(Env, Ei1, Eo, T).
infer(_, X, X, int) :- integer(X).
infer(_, X, X, float) :- float(X).
%% !!!À COMPLÉTER!!!

%% Regle de typage 1 : Inference du type d'une variable
%%(recherche dans l'environement son type)
infer(Env,X,X,T) :- lookup(Env,X,T).

%% Regle de typage 2: Inference du type d'une fonction
infer(Env, fun(X, E1, E2), fun(X, Eo1, Eo2), arw(X, E1, E3)) :- 
                                    check(Env, E1, type, Eo1),
                                    infer([X:E1|Env], E2, Eo2, E3).

%% Regle de typage 4: Inference du type "type" au type d'une fonction
infer(Env, arw(X,E1,E2), arw(X,Eo1,Eo2),type) :- 
                                    check(Env,E1,type,Eo1), 
                                    check([X:E1|Env],E2,type,Eo2).

%% Regle de typage 5: Inference du type "type" de forall().
infer(Env,forall(X,E1,E2), forall(X,Eo1,Eo2), type) :- 
                                    check(Env, E1, type, Eo1), 
                                    check([X:Eo1|Env],E2,type, Eo2).

%% Regle de typage 6: Inference du type d'un appel de fonction.
infer(Env, app(E1, E2), app(Eo1, Eo22), T) :- 
                                    %%infer le type de E2 pour que
                                    %%notre type arw de E1 match
                                    %%et qu'on puisse effectuer
                                    %%la magie de prolog dans coerce
                                    infer(Env, E2, Eo2, E4), 
                                    check(Env, E1, arw(X,E4,E5), Eo1),
                                    check(Env, Eo2, E4, Eo22), 
                                    subst(Env, X, Eo22, E5, T).

%%Quand le type de E1 est deja connu
infer(Env, app(E1, E2), app(Eo1, Eo2), T) :- 
                                infer(Env, E1, Eo1, arw(X,E4,E5)), 
                                check(Env, E2, E4, Eo2), 
                                subst(Env, X, Eo2, E5, T).

%% Regle de typage 7: Inference du type d'une déclaration.
infer(Env, let(X, E1, E2, E3), let(X, Eo1, Eo2, Eo3), T) :- 
                                    check(Env, E1, type, Eo1),
                                    check([X:Eo1|Env], E2, Eo1, Eo2),
                                    infer([X:Eo1|Env], E3, Eo3, T).

%% Regle de typage 8: Inference du type d'une déclaration avec un
%%                                                      argument implicite.
infer(Env, let(X, E2, E3), let(X, E1, Eo2, Eo3), E4) :- 
                                    infer([X:E1|Env], E2, Eo2, E1), 
                                    infer([X:E1|Env], E3, Eo3, E4).

%% Regle de typage 9: Inference de type explicite.
infer(Env, (E1 : E2), Eo, T) :- check(Env, E2, type, T),
                                check(Env, E1, T, Eo).


                                  




%% check(+Env, +Ei, +T, -Eo)
%% Élabore Ei (dans un contexte Env) en Eo, en s'assurant que son type soit T.
check(_Env, MV, _, Eo) :-
    %% On ne fait pas l'effort de se souvenir du type des métavariables,
    %% donc on ne peut pas vérifier si MV a effectivement le type attendu.
    %% À la place, on accepte n'importe quel usage de métavariables, en
    %% espérant qu'elles sont utilisées correctement.  C'est généralement le
    %% cas de toute façon, et pour les cas restants on se repose sur le filet
    %% de sécurité qu'est `verify`.
    var(MV), !, Eo = MV.
check(Env, Ei, T, Eo) :- expand(Ei, Ei1), check(Env, Ei1, T, Eo).

%% Regle de typage 3: Check type d'une fonction ayant un sucre syntaxique
check(Env, fun(X, E2), arw(X, E1, E3), fun(X, E1, Eo2)) :- 
                            check([(X:E1)|Env], E2, E3, Eo2). 
%% Regle de typage 11: Check d'un forall(): 
check(Env, E1, forall(X, E2, E3), Eo) :- check([(X:E2)|Env], E1, E3, Eo).


%% Finalement, cas par défaut:
check(Env, Ei, T, Eo) :- %%write('\n\n\nMAYEB?!\n\n\n'),write('Ei ='(Ei))
                                        %%,write('T ='(T)),write('Eo ='(Eo)),
    infer(Env, Ei, Eo1, T1),  %%write('\n\n\nOOOHH?!\n\n\n'),
    (coerce(Env, Eo1, T1, T, Eo) -> true).


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Environnement initial et tests %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


elaborate_env(Env, [], Env).
elaborate_env(Env, [X:Ti|Envi], Envo) :-
    check(Env, Ti, type, To) ->
        write('\nPasse le check '(Ti)),
        write('   '),
        (verify(Env, To, type) -> write('\nVerified: '(To)), write("\n"),
             elaborate_env([X:To|Env], Envi, Envo));
    write(user_error, 'FAILED_TO_ELABORATE'(Ti)), nl(user_error), !, fail.

initenv(Env) :-
    elaborate_env(
        [type : type],
        [int :  type,
         float :  type,
         bool :  type,
         int_to_float : (int -> float),
         int_to_bool : (int -> bool),
         list : (type -> int -> type),
         (+) : (int -> int -> int),
         (-) : (int -> int -> int),
         (*) : (int -> int -> int),
         (/) : (float -> float -> float),
         (<) : (float -> float -> int),
         if : forall(t, (bool -> t -> t -> t)),
         nil :  forall(t, list(t, 0)),
         identity : forall(t, (t -> t)),
         cons : forall(t, 
                        forall(n,
                                (t -> list(t, n) -> list(t, n + 1))))],
        Env).

%% Quelques expressions pour nos tests.
sample(1 + 2).
sample(1 / 2).
sample(identity(3)).
sample(cons(13,nil)).
sample(cons(1.0, cons(2.0, nil))).
sample(let([fact(n:int) = if(n < 2, 1, n * fact(n - 1))],
           fact(44))).
sample(let([fact(n) : (int -> int) = if(n < 2, 1, n * fact(n - 1))],
           fact(45))).
sample(let([list1 : forall(a, (a -> list(a, 1))) = fun(x, cons(x, nil))],
           list1(42))).
sample(let([list1(x) : forall(a, (a -> list(a, 1))) = cons(x, nil)],
           list1(43))).
sample(let([pushn(n,l) : arw(n, _, (list(int,n) -> list(int,n+1))) = cons(n,l)],
           %% L'argument `n` ne peut être que 0, ici, et on peut l'inférer!
           pushn(_,nil))).

%% Roule le test sur une expression.
test_sample(Env, E) :-
    infer(Env, E, Eo, T) -> 
        normalize(Env, T, T1),
        write(user_error, inferred(E, T1)), nl(user_error),
        write(user_error, verifying(Eo)), nl(user_error),
        (verify(Env, Eo, T) ->
             write(user_error, 'VERIFIED!!'), nl(user_error);
         write(user_error, 'FAILED_TO_VERIFY'(Eo)), nl(user_error));
    write(user_error, 'FAILED_TO_INFER'(E)), nl(user_error).

%% Roule le test sur chacune des expressions de `sample`.
test_samples :-
    initenv(Env), sample(E), test_sample(Env, E).

