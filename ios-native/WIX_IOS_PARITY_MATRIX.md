# Inventaire des routes Wix et des écrans iOS

Date de relevé : 18 octobre 2026. Source Wix : `src/components/Router.tsx` sur la branche `main`, consultée en lecture seule. Source iOS : `ios-native/RootView.swift` et services du projet local.

## Règle de lecture

L’entrée « Explorer toutes les pages du site » ouvre la WKWebView persistante; celle-ci utilise le routeur Wix et garde la session du site. Les routes ci-dessous sont donc servies par le site lorsqu’un lien ou un parcours autorisé y mène. Les routes d’administration restent soumises aux droits Wix. Les pages marquées « complément natif » ont aussi un écran ou une action iOS décrit dans l’inventaire fonctionnel. Cela ne signifie pas que toutes leurs fonctionnalités ont été recréées en SwiftUI : plusieurs domaines natifs restent partiels.

Routes trouvées : **207 déclarations**. Cela comprend les motifs avec paramètres et les trois routes de ville construites depuis des listes.

## Vérification directe des routes publiques — 18 octobre 2026

Contrôle visuel en lecture seule du site public dans un navigateur, sans connexion ni soumission de formulaire. Cela vérifie que les routes d’exemple ouvrent une page visible sur le site; ce n’est ni un essai de l’application iOS ni une preuve de parité fonctionnelle pour toutes les routes.

| Route contrôlée | Résultat observé sur le site | Portée / limite |
|---|---|---|
| `/` | Accueil rendu; navigation vers les annonces, professionnels, services, comptes et pages d’information visible. | La source iOS ouvre cette origine dans le composant WKWebView commun. Le rendu dans l’application et sur appareil n’a pas été observé pendant ce contrôle. |
| `/annonces` | Catalogue immobilier rendu avec carte, filtres, types de vendeurs et action de recherche. | Contrôle de chargement et d’interface; les filtres n’ont pas été soumis. |
| `/petites-annonces` | Page publique rendue avec actions de recherche et de dépôt et catégories vente/don/échange/location. | Contrôle de chargement; dépôt, paiement et contact non exécutés. |
| `/professionnels` | Annuaire rendu avec recherche et fiches de professionnels. | Contrôle de chargement; favoris et contact nécessitent des essais séparés. |
| `/locations-saisonnieres` | Page de séjours rendue avec destination, dates, voyageurs et recherche. | Contrôle de chargement; aucune recherche ni réservation n’a été soumise. |
| `/matching-immobilier` | Page explicative du matching rendue. | Cette route est informative; elle ne constitue pas, à elle seule, le parcours opérationnel de matching qui se trouve dans les espaces connectés. |
| `/pro-app-login` | Formulaire professionnel rendu avec connexion, compte déjà inscrit et inscription. | Aucun identifiant n’a été saisi; le succès de connexion et la redirection ne sont pas vérifiés. |
| `/vendeur-dashboard` | Le site montre un formulaire « Connexion Vendeur » à l’accès non connecté. | Confirme la protection de cet espace; aucun compte n’a été utilisé pour vérifier le dashboard après connexion. |
| `/pro/dashboard` | Le site affiche « Sign In Required » et une action de connexion à l’accès non connecté. | Confirme la protection de cet espace; les données et actions du dashboard restent non vérifiées. |
| `/broker-dashboard` | Le site montre le formulaire de connexion Courtier. | Page d’entrée vérifiée sans soumission de compte. |
| `/artisan-dashboard` | Le site montre le formulaire de connexion Artisan. | La route sert aussi à l’entrée diagnostiqueur dans le mapping iOS; l’identité métier n’est pas distinguable par l’URL seule. |
| `/espace-prestataire` | Le site montre le formulaire de connexion Prestataire. | Page d’entrée vérifiée sans soumission de compte. |
| `/hebergeur-dashboard` | Le site affiche la connexion Hébergeur. | Page d’entrée vérifiée sans soumission de compte. |
| `/vacancier-connexion` | Redirection observée vers `/vendeur-login`, qui affiche « Connexion Vendeur ». | Le parcours voyageur doit être validé avec un vrai compte : le libellé et la destination observés sont ceux du vendeur. |
| `/vendeur-reservations-saisonnieres` | La page affiche une demande de connexion dans le formulaire vendeur. | Les réservations sont protégées; la connexion voyageur et le retour à cette page ne sont pas validés. |

**Conclusion de ce contrôle :** les quinze routes énumérées ont été ouvertes directement; les catalogues publics affichent leur contenu, les dashboards contrôlés présentent leur écran d’accès, et l’entrée voyageur redirige actuellement vers la connexion vendeur. Les 207 déclarations n’ont pas été exécutées une par une : plusieurs sont des motifs avec paramètres (identifiants, villes, catégories), des routes d’administration, de paiement ou des parcours nécessitant un compte. Le routeur iOS permet le chargement HTTP(S) et les liens ouvrant une nouvelle fenêtre sont repris dans la même WKWebView (voir `ProfessionalPortalWebViewRepresentable` dans `RootView.swift`); ce constat de code ne démontre pas que chaque interaction Wix fonctionne dans WKWebView. La compilation CodeMagic #57 valide l’archive, pas les comportements métier. Une comparaison exacte des 207 parcours demande des essais sur l’app iOS avec des comptes de chaque rôle et des données contrôlées.

### Contrôle des bascules après connexion par rôle

- Les rôles particulier, courtier, artisan/diagnostiqueur, prestataire et hébergeur ouvrent maintenant leurs routes de connexion et d’inscription via le composant WKWebView commun, qui partage le magasin de cookies et renvoie vers l’écran d’app après détection du chemin de dashboard attendu. Le pro immobilier suit `/api/pro-app-login` et transmet son jeton à la même WKWebView.
- Correction locale du 18 octobre 2026 : deux anciens modificateurs `.sheet` pour connexion/inscription ouvraient une vue Safari concurrente. Ils ont été retirés pour ne laisser que le flux WKWebView qui conserve la session et reçoit la redirection. Vérification statique ajoutée au script `verify:ios-matching`; compilation iOS de cette dernière modification non lancée.
- Pour artisan et diagnostiqueur, les URL de connexion, inscription et dashboard sont identiques. Le code conserve le rôle choisi par l’utilisateur; le chemin `/artisan-dashboard` ne permet pas de confirmer le rôle effectif retourné par le compte. L’identité métier doit être vérifiée par le site ou lors d’un essai avec chaque compte.
- Le voyageur est ouvert dans la WKWebView sur `/vacancier-connexion`, mais le site a redirigé ce chemin vers `/vendeur-login` lors du contrôle public. Les favoris saisonniers, réservations et messages du voyageur ne sont pas reproduits nativement et leur parcours authentifié reste non vérifié. Il s’agit d’un écart à clarifier côté site; aucune modification Wix n’a été effectuée.
- Les actions Messages et Parrainage sont adaptées au rôle dans le dashboard natif lorsque celui-ci est utilisé : la section native expose messages aux rôles pris en charge et le parrainage natif particulier/pro immobilier. Pour les autres comptes à session Wix personnalisée, le dashboard est rendu par le site dans la WKWebView; la présence et le comportement de chaque bouton sur compte connecté n’ont pas été testés. Le port natif n’est donc pas complet pour tous les rôles.

## Accès aux comptes par rôle

| Espace | Connexion Wix | Inscription Wix | Mot de passe oublié | Tableau de bord Wix | État côté iOS |
|---|---|---|---|---|---|
| Particulier | `/vendeur-login` | `/vendeur-signup` | `/vendeur-forgot-password` | `/vendeur-dashboard` | Connexion/inscription/récupération et tableau de bord dans la même WKWebView persistante; l’app bascule automatiquement sur le dashboard quand Wix y redirige après connexion. Les API SwiftUI natives restent liées à la session Wix Members. |
| Professionnel immobilier | `/pro-app-login` | `/pro-app-login?mode=signup` | Écran de connexion Pro App | `/pro/dashboard` | Connexion directe à la même API Pro App; jeton conservé dans le Trousseau et transmis au site. Dashboard web embarqué; push iOS relié au profil Wix via Supabase v5. |
| Courtier | `/broker-login` | `/broker-signup` | `/broker-forgot-password` | `/broker-dashboard` | Connexion/inscription/récupération et dashboard du site dans la WKWebView persistante; détection de la redirection vers le dashboard. Les fonctions SwiftUI restent liées à une session Wix Members. |
| Artisan | `/artisan-login` | `/artisan-signup` | `/artisan-forgot-password` | `/artisan-dashboard` | Partage les routes de compte avec le diagnostiqueur; dashboard du site ouvert dans la WKWebView persistante après connexion. Les fonctions SwiftUI restent liées à une session Wix Members. |
| Diagnostiqueur | `/artisan-login` | `/artisan-signup` | `/artisan-forgot-password` | `/artisan-dashboard` | Même système de compte que la fiche artisan/diagnostiqueur; dashboard du site ouvert dans la WKWebView persistante après connexion. Les fonctions SwiftUI restent liées à une session Wix Members. |
| Prestataire de services | `/connexion-prestataire` | `/inscription-prestataire` | `/mot-de-passe-oublie-prestataire` | `/espace-prestataire` | Connexion/inscription/récupération et dashboard du site dans la WKWebView persistante; détection de la redirection vers le dashboard. Les fonctions SwiftUI restent liées à une session Wix Members. |
| Hébergeur saisonnier | `/hebergeur-connexion` | `/hebergeur-inscription` | `/hebergeur-mot-de-passe-oublie` | `/hebergeur-dashboard` | Connexion/inscription/récupération et dashboard du site dans la WKWebView persistante; détection de la redirection vers le dashboard. Les fonctions SwiftUI restent liées à une session Wix Members. |
| Voyageur / vacancier | `/vacancier-connexion` | `/vacancier-inscription` | Parcours du site | `/vendeur-reservations-saisonnieres` et `/vendeur-messages-hebergeurs` | L’entrée voyageur ouvre la WebView; favoris, réservations et messagerie voyageur ne sont pas encore reproduits en natif. |

## Routes Wix et mode d’accès iOS

| # | Route Wix | Dans l’app | Complément natif identifié |
|---:|---|---|---|
| 1 | `/petites-annonces-${city.slug}` | WKWebView du site | WebView; pas de parité native complète établie |
| 2 | `/annonces-immobilieres-${city.slug}` | WKWebView du site | WebView; pas de parité native complète établie |
| 3 | `/matching-immobilier-${city.slug}` | WKWebView du site | WebView; pas de parité native complète établie |
| 4 | `/${prefix}/:ville` | WKWebView du site | WebView; pas de parité native complète établie |
| 5 | `/${prefix}/:activite/:ville` | WKWebView du site | WebView; pas de parité native complète établie |
| 6 | `/${prefix}/:ville/quartier/:quartier` | WKWebView du site | WebView; pas de parité native complète établie |
| 7 | `/${prefix}/:activite/:ville/quartier/:quartier` | WKWebView du site | WebView; pas de parité native complète établie |
| 8 | `/petites-annonces/ville/:ville` | WKWebView du site | WebView; pas de parité native complète établie |
| 9 | `/petites-annonces/ville/:ville/quartier/:quartier` | WKWebView du site | WebView; pas de parité native complète établie |
| 10 | `/petites-annonces/categorie/:categorie/ville/:ville` | WKWebView du site | WebView; pas de parité native complète établie |
| 11 | `/petites-annonces/categorie/:categorie/ville/:ville/quartier/:quartier` | WKWebView du site | WebView; pas de parité native complète établie |
| 12 | `/` | WKWebView du site | Oui, couverture partielle; voir la matrice fonctionnelle |
| 13 | `/devenir-mandataire-immobilier` | WKWebView du site | WebView; pas de parité native complète établie |
| 14 | `/actualites` | WKWebView du site | WebView; pas de parité native complète établie |
| 15 | `/actualites/:slug` | WKWebView du site | WebView; pas de parité native complète établie |
| 16 | `/location` | WKWebView du site | WebView; pas de parité native complète établie |
| 17 | `/mise-location` | WKWebView du site | WebView; pas de parité native complète établie |
| 18 | `/achat` | WKWebView du site | WebView; pas de parité native complète établie |
| 19 | `/estimation` | WKWebView du site | Oui, couverture partielle; voir la matrice fonctionnelle |
| 20 | `/espace-pro` | WKWebView du site | WebView; pas de parité native complète établie |
| 21 | `/professionnels` | WKWebView du site | Oui, couverture partielle; voir la matrice fonctionnelle |
| 22 | `/professionnels/:id` | WKWebView du site | WebView; pas de parité native complète établie |
| 23 | `/professionnel/:category/:slug` | WKWebView du site | WebView; pas de parité native complète établie |
| 24 | `/revendiquer-profil` | WKWebView du site | WebView; pas de parité native complète établie |
| 25 | `/nos-courtiers` | WKWebView du site | WebView; pas de parité native complète établie |
| 26 | `/pros` | WKWebView du site | WebView; pas de parité native complète établie |
| 27 | `/inscription-pro` | WKWebView du site | WebView; pas de parité native complète établie |
| 28 | `/pro-app-login` | WKWebView du site | WebView; pas de parité native complète établie |
| 29 | `/annonces` | WKWebView du site | Oui, couverture partielle; voir la matrice fonctionnelle |
| 30 | `/annonce-immobiliere-gratuite` | WKWebView du site | WebView; pas de parité native complète établie |
| 31 | `/deposer-annonce-gratuite` | WKWebView du site | WebView; pas de parité native complète établie |
| 32 | `/immobilier/:ville` | WKWebView du site | WebView; pas de parité native complète établie |
| 33 | `/maison-a-vendre/:ville` | WKWebView du site | WebView; pas de parité native complète établie |
| 34 | `/appartement-a-vendre/:ville` | WKWebView du site | WebView; pas de parité native complète établie |
| 35 | `/maison-a-louer/:ville` | WKWebView du site | WebView; pas de parité native complète établie |
| 36 | `/appartement-a-louer/:ville` | WKWebView du site | WebView; pas de parité native complète établie |
| 37 | `/petites-annonces-gratuites` | WKWebView du site | WebView; pas de parité native complète établie |
| 38 | `/vendre-bien-immobilier-sans-agence` | WKWebView du site | WebView; pas de parité native complète établie |
| 39 | `/trouver-professionnel-local` | WKWebView du site | WebView; pas de parité native complète établie |
| 40 | `/referencer-son-entreprise` | WKWebView du site | WebView; pas de parité native complète établie |
| 41 | `/pourquoi-partenairefoyer` | WKWebView du site | WebView; pas de parité native complète établie |
| 42 | `/a-propos` | WKWebView du site | WebView; pas de parité native complète établie |
| 43 | `/petites-annonces` | WKWebView du site | Oui, couverture partielle; voir la matrice fonctionnelle |
| 44 | `/petites-annonces/categorie/:categorySlug` | WKWebView du site | WebView; pas de parité native complète établie |
| 45 | `/petites-annonces/categorie/:categorySlug/*` | WKWebView du site | WebView; pas de parité native complète établie |
| 46 | `/petites-annonces/checkout/:adId` | WKWebView du site | WebView; pas de parité native complète établie |
| 47 | `/petites-annonces/paiement-confirme` | WKWebView du site | WebView; pas de parité native complète établie |
| 48 | `/petites-annonces/:slug` | WKWebView du site | WebView; pas de parité native complète établie |
| 49 | `/annonce/:slug` | WKWebView du site | WebView; pas de parité native complète établie |
| 50 | `/annonce-immobiliere/:slug` | WKWebView du site | WebView; pas de parité native complète établie |
| 51 | `/pro/dashboard` | WKWebView du site | Oui, couverture partielle; voir la matrice fonctionnelle |
| 52 | `/pro/profil` | WKWebView du site | WebView; pas de parité native complète établie |
| 53 | `/pro/biens` | WKWebView du site | Oui, couverture partielle; voir la matrice fonctionnelle |
| 54 | `/pro/acquereurs` | WKWebView du site | Oui, couverture partielle; voir la matrice fonctionnelle |
| 55 | `/pro/demandes` | WKWebView du site | Oui, couverture partielle; voir la matrice fonctionnelle |
| 56 | `/pro/demandes-acceptees` | WKWebView du site | Oui, couverture partielle; voir la matrice fonctionnelle |
| 57 | `/pro/matching` | WKWebView du site | Oui, couverture partielle; voir la matrice fonctionnelle |
| 58 | `/pro/mes-matchings` | WKWebView du site | Oui, couverture partielle; voir la matrice fonctionnelle |
| 59 | `/pro/messages` | WKWebView du site | Oui, couverture partielle; voir la matrice fonctionnelle |
| 60 | `/pro/messages-annonces` | WKWebView du site | Oui, couverture partielle; voir la matrice fonctionnelle |
| 61 | `/pro/abonnement` | WKWebView du site | Oui, couverture partielle; voir la matrice fonctionnelle |
| 62 | `/pro/guide-utilisation` | WKWebView du site | WebView; pas de parité native complète établie |
| 63 | `/pro/analyse-marche` | WKWebView du site | WebView; pas de parité native complète établie |
| 64 | `/pro/actualites/:id` | WKWebView du site | WebView; pas de parité native complète établie |
| 65 | `/recherche-location` | WKWebView du site | Oui, couverture partielle; voir la matrice fonctionnelle |
| 66 | `/mise-en-location` | WKWebView du site | WebView; pas de parité native complète établie |
| 67 | `/recherche-achat` | WKWebView du site | Oui, couverture partielle; voir la matrice fonctionnelle |
| 68 | `/estimation-bien` | WKWebView du site | Oui, couverture partielle; voir la matrice fonctionnelle |
| 69 | `/comment-ca-marche` | WKWebView du site | WebView; pas de parité native complète établie |
| 70 | `/parrainage` | WKWebView du site | WebView; pas de parité native complète établie |
| 71 | `/pro/opportunites-filleuls` | WKWebView du site | WebView; pas de parité native complète établie |
| 72 | `/pro/parrainage` | WKWebView du site | WebView; pas de parité native complète établie |
| 73 | `/pro/minisite-demandes` | WKWebView du site | WebView; pas de parité native complète établie |
| 74 | `/pro/estimation` | WKWebView du site | WebView; pas de parité native complète établie |
| 75 | `/pro/mes-estimations` | WKWebView du site | WebView; pas de parité native complète établie |
| 76 | `/pro/campaign-test` | WKWebView du site | WebView; pas de parité native complète établie |
| 77 | `/brevo-template19-debug` | WKWebView du site | WebView; pas de parité native complète établie |
| 78 | `/pro/campaign-automation` | WKWebView du site | WebView; pas de parité native complète établie |
| 79 | `/buyer-followup-diagnostic` | WKWebView du site | WebView; pas de parité native complète établie |
| 80 | `/estimation-immobiliere` | WKWebView du site | Oui, couverture partielle; voir la matrice fonctionnelle |
| 81 | `/matching-immobilier` | WKWebView du site | WebView; pas de parité native complète établie |
| 82 | `/trouver-acquereur-immobilier` | WKWebView du site | WebView; pas de parité native complète établie |
| 83 | `/inter-agence-immobilier` | WKWebView du site | WebView; pas de parité native complète établie |
| 84 | `/logiciel-mandataire-immobilier` | WKWebView du site | WebView; pas de parité native complète établie |
| 85 | `/mini-site-agent-immobilier` | WKWebView du site | WebView; pas de parité native complète établie |
| 86 | `/outil-mandataire-immobilier` | WKWebView du site | WebView; pas de parité native complète établie |
| 87 | `/mandataire-immobilier-loire-atlantique` | WKWebView du site | WebView; pas de parité native complète établie |
| 88 | `/artisan-login` | WKWebView du site | WebView; pas de parité native complète établie |
| 89 | `/artisan-signup` | WKWebView du site | WebView; pas de parité native complète établie |
| 90 | `/artisan-profile/:slug` | WKWebView du site | WebView; pas de parité native complète établie |
| 91 | `/artisan-dashboard` | WKWebView du site | Oui, couverture partielle; voir la matrice fonctionnelle |
| 92 | `/artisan-profile-edit` | WKWebView du site | WebView; pas de parité native complète établie |
| 93 | `/artisan-messages` | WKWebView du site | Oui, couverture partielle; voir la matrice fonctionnelle |
| 94 | `/artisan-forgot-password` | WKWebView du site | WebView; pas de parité native complète établie |
| 95 | `/artisan-reset-password` | WKWebView du site | WebView; pas de parité native complète établie |
| 96 | `/artisan-change-password` | WKWebView du site | WebView; pas de parité native complète établie |
| 97 | `/tarifs` | WKWebView du site | WebView; pas de parité native complète établie |
| 98 | `/admin-login` | WKWebView du site | WebView; pas de parité native complète établie |
| 99 | `/admin` | WKWebView du site | WebView; pas de parité native complète établie |
| 100 | `/admin-password-reset` | WKWebView du site | WebView; pas de parité native complète établie |
| 101 | `/lahaye-baptiste` | WKWebView du site | WebView; pas de parité native complète établie |
| 102 | `/referral-code-migration` | WKWebView du site | WebView; pas de parité native complète établie |
| 103 | `/minisite/:slug` | WKWebView du site | WebView; pas de parité native complète établie |
| 104 | `/pro/:slug` | WKWebView du site | WebView; pas de parité native complète établie |
| 105 | `/broker-login` | WKWebView du site | WebView; pas de parité native complète établie |
| 106 | `/broker-signup` | WKWebView du site | WebView; pas de parité native complète établie |
| 107 | `/broker-dashboard` | WKWebView du site | Oui, couverture partielle; voir la matrice fonctionnelle |
| 108 | `/broker-profile-edit` | WKWebView du site | WebView; pas de parité native complète établie |
| 109 | `/broker-forgot-password` | WKWebView du site | WebView; pas de parité native complète établie |
| 110 | `/broker-reset-password` | WKWebView du site | WebView; pas de parité native complète établie |
| 111 | `/broker-change-password` | WKWebView du site | WebView; pas de parité native complète établie |
| 112 | `/broker-profile/:id` | WKWebView du site | WebView; pas de parité native complète établie |
| 113 | `/brokers-directory` | WKWebView du site | WebView; pas de parité native complète établie |
| 114 | `/broker-messages` | WKWebView du site | Oui, couverture partielle; voir la matrice fonctionnelle |
| 115 | `/vendeur-login` | WKWebView du site | WebView; pas de parité native complète établie |
| 116 | `/vendeur-signup` | WKWebView du site | WebView; pas de parité native complète établie |
| 117 | `/vendeur-forgot-password` | WKWebView du site | WebView; pas de parité native complète établie |
| 118 | `/vendeur-reinitialiser-mot-de-passe` | WKWebView du site | WebView; pas de parité native complète établie |
| 119 | `/vendeur-dashboard` | WKWebView du site | Oui, couverture partielle; voir la matrice fonctionnelle |
| 120 | `/deposer-mon-bien` | WKWebView du site | Oui, couverture partielle; voir la matrice fonctionnelle |
| 121 | `/vendeur-property/:id` | WKWebView du site | WebView; pas de parité native complète établie |
| 122 | `/vendeur-matching/:id` | WKWebView du site | WebView; pas de parité native complète établie |
| 123 | `/vendeur-matchings` | WKWebView du site | Oui, couverture partielle; voir la matrice fonctionnelle |
| 124 | `/professionnels-compatibles` | WKWebView du site | WebView; pas de parité native complète établie |
| 125 | `/vendeur-profil` | WKWebView du site | WebView; pas de parité native complète établie |
| 126 | `/vendeur-bien/:id/edit` | WKWebView du site | WebView; pas de parité native complète établie |
| 127 | `/vendeur-photos` | WKWebView du site | WebView; pas de parité native complète établie |
| 128 | `/vendeur-favoris` | WKWebView du site | Oui, couverture partielle; voir la matrice fonctionnelle |
| 129 | `/vendeur-petites-annonces` | WKWebView du site | Oui, couverture partielle; voir la matrice fonctionnelle |
| 130 | `/vendeur-petites-annonces/creer` | WKWebView du site | WebView; pas de parité native complète établie |
| 131 | `/vendeur-modifier-annonce/:id` | WKWebView du site | WebView; pas de parité native complète établie |
| 132 | `/pro-private-property-matching` | WKWebView du site | WebView; pas de parité native complète établie |
| 133 | `/pro/matchings-particuliers` | WKWebView du site | WebView; pas de parité native complète établie |
| 134 | `/private-property-matching-diagnostic` | WKWebView du site | WebView; pas de parité native complète établie |
| 135 | `/matching-diagnostic` | WKWebView du site | WebView; pas de parité native complète établie |
| 136 | `/template18-deletion-diagnostic` | WKWebView du site | WebView; pas de parité native complète établie |
| 137 | `/template18-runtime-diagnostic` | WKWebView du site | WebView; pas de parité native complète établie |
| 138 | `/template18-runtime-complete` | WKWebView du site | WebView; pas de parité native complète établie |
| 139 | `/data-normalization-diagnostic` | WKWebView du site | WebView; pas de parité native complète établie |
| 140 | `/property-owner-repair` | WKWebView du site | WebView; pas de parité native complète établie |
| 141 | `/diagnostic-bien-1m` | WKWebView du site | WebView; pas de parité native complète établie |
| 142 | `/diagnostic-member-id` | WKWebView du site | WebView; pas de parité native complète établie |
| 143 | `/fix-test-envoie` | WKWebView du site | WebView; pas de parité native complète établie |
| 144 | `/fix-and-verify-test-envoie` | WKWebView du site | WebView; pas de parité native complète établie |
| 145 | `/diagnostic-and-fix-test-envoie` | WKWebView du site | WebView; pas de parité native complète établie |
| 146 | `/imported-listings-diagnostic` | WKWebView du site | WebView; pas de parité native complète établie |
| 147 | `/repair-imported-listings` | WKWebView du site | WebView; pas de parité native complète établie |
| 148 | `/admin/actualites-dashboard` | WKWebView du site | WebView; pas de parité native complète établie |
| 149 | `/admin/moderation-petites-annonces` | WKWebView du site | WebView; pas de parité native complète établie |
| 150 | `/template22-template23-test` | WKWebView du site | WebView; pas de parité native complète établie |
| 151 | `/test-emails-real-flow` | WKWebView du site | WebView; pas de parité native complète établie |
| 152 | `/template23-diagnostic` | WKWebView du site | WebView; pas de parité native complète établie |
| 153 | `/template22-diagnostic` | WKWebView du site | WebView; pas de parité native complète établie |
| 154 | `/template19-real-flow-test` | WKWebView du site | WebView; pas de parité native complète établie |
| 155 | `/mes-professionnels-favoris` | WKWebView du site | WebView; pas de parité native complète établie |
| 156 | `/services-du-quotidien` | WKWebView du site | WebView; pas de parité native complète établie |
| 157 | `/locations-saisonnieres` | WKWebView du site | Oui, couverture partielle; voir la matrice fonctionnelle |
| 158 | `/location-saisonniere/:slug` | WKWebView du site | WebView; pas de parité native complète établie |
| 159 | `/hebergeur-inscription` | WKWebView du site | WebView; pas de parité native complète établie |
| 160 | `/hebergeur-connexion` | WKWebView du site | WebView; pas de parité native complète établie |
| 161 | `/hebergeur-mot-de-passe-oublie` | WKWebView du site | WebView; pas de parité native complète établie |
| 162 | `/hebergeur-reinitialiser-mot-de-passe` | WKWebView du site | WebView; pas de parité native complète établie |
| 163 | `/hebergeur-dashboard` | WKWebView du site | Oui, couverture partielle; voir la matrice fonctionnelle |
| 164 | `/hebergeur-hebergements` | WKWebView du site | Oui, couverture partielle; voir la matrice fonctionnelle |
| 165 | `/hebergeur-hebergements-nouveau` | WKWebView du site | WebView; pas de parité native complète établie |
| 166 | `/hebergeur-hebergements-edit/:id` | WKWebView du site | WebView; pas de parité native complète établie |
| 167 | `/hebergeur-calendrier` | WKWebView du site | Oui, couverture partielle; voir la matrice fonctionnelle |
| 168 | `/hebergeur-calendrier/:accommodationId` | WKWebView du site | WebView; pas de parité native complète établie |
| 169 | `/hebergeur-demandes` | WKWebView du site | Oui, couverture partielle; voir la matrice fonctionnelle |
| 170 | `/hebergeur-messages` | WKWebView du site | Oui, couverture partielle; voir la matrice fonctionnelle |
| 171 | `/hebergeur-abonnement` | WKWebView du site | Oui, couverture partielle; voir la matrice fonctionnelle |
| 172 | `/hebergeur-profil` | WKWebView du site | WebView; pas de parité native complète établie |
| 173 | `/vacancier-inscription` | WKWebView du site | WebView; pas de parité native complète établie |
| 174 | `/vacancier-connexion` | WKWebView du site | WebView; pas de parité native complète établie |
| 175 | `/vendeur-favoris-saisonniers` | WKWebView du site | WebView; pas de parité native complète établie |
| 176 | `/vendeur-reservations-saisonnieres` | WKWebView du site | WebView; pas de parité native complète établie |
| 177 | `/vendeur-messages-hebergeurs` | WKWebView du site | WebView; pas de parité native complète établie |
| 178 | `/connexion-prestataire` | WKWebView du site | WebView; pas de parité native complète établie |
| 179 | `/inscription-prestataire` | WKWebView du site | WebView; pas de parité native complète établie |
| 180 | `/mot-de-passe-oublie-prestataire` | WKWebView du site | WebView; pas de parité native complète établie |
| 181 | `/espace-prestataire` | WKWebView du site | Oui, couverture partielle; voir la matrice fonctionnelle |
| 182 | `/espace-prestataire/creer-fiche` | WKWebView du site | WebView; pas de parité native complète établie |
| 183 | `/espace-prestataire/modifier-fiche` | WKWebView du site | WebView; pas de parité native complète établie |
| 184 | `/espace-prestataire/photos` | WKWebView du site | WebView; pas de parité native complète établie |
| 185 | `/prestataire/:slug` | WKWebView du site | WebView; pas de parité native complète établie |
| 186 | `/reinitialisation-mot-de-passe-prestataire` | WKWebView du site | WebView; pas de parité native complète établie |
| 187 | `/partner-geocoding-diagnostic` | WKWebView du site | WebView; pas de parité native complète établie |
| 188 | `/*` | WKWebView du site | WebView; pas de parité native complète établie |
| 189 | `/` | WKWebView du site | Oui, couverture partielle; voir la matrice fonctionnelle |
| 190 | `/autorisation-diffusion-annonces` | WKWebView du site | WebView; pas de parité native complète établie |
| 191 | `/cgv` | WKWebView du site | WebView; pas de parité native complète établie |
| 192 | `/cgu` | WKWebView du site | WebView; pas de parité native complète établie |
| 193 | `/mentions-legales` | WKWebView du site | WebView; pas de parité native complète établie |
| 194 | `/confidentialite` | WKWebView du site | WebView; pas de parité native complète établie |
| 195 | `/broker-cgu` | WKWebView du site | WebView; pas de parité native complète établie |
| 196 | `/broker-cgv` | WKWebView du site | WebView; pas de parité native complète établie |
| 197 | `/artisan-cgu` | WKWebView du site | WebView; pas de parité native complète établie |
| 198 | `/artisan-cgv` | WKWebView du site | WebView; pas de parité native complète établie |
| 199 | `/pro-cgu` | WKWebView du site | WebView; pas de parité native complète établie |
| 200 | `/pro-cgv` | WKWebView du site | WebView; pas de parité native complète établie |
| 201 | `/cgu-particuliers` | WKWebView du site | WebView; pas de parité native complète établie |
| 202 | `/prestataire-cgu` | WKWebView du site | WebView; pas de parité native complète établie |
| 203 | `/prestataire-cgv` | WKWebView du site | WebView; pas de parité native complète établie |
| 204 | `/cookies` | WKWebView du site | WebView; pas de parité native complète établie |
| 205 | `/conditions-parrainage` | WKWebView du site | WebView; pas de parité native complète établie |
| 206 | `/regles-annonces` | WKWebView du site | WebView; pas de parité native complète établie |
| 207 | `/suppression-compte` | WKWebView du site | WebView; pas de parité native complète établie |

## Écrans et parcours natifs recensés

### Navigation et découverte

- `RootView`
- `HomeDashboardView`
- `NativeListingsView`
- `NativeSeasonalStaysView`
- `NativeProfessionalsView`
- `NativeSpacePickerView`

### Fiches, formulaires et demandes

- The property catalogue opens the matching public Wix announcement page in the in-app WKWebView so published detail-page changes are used without an iOS rebuild.
- `NativeClassifiedAdDetailView`
- `NativePrivatePropertyForm`
- `NativeProfessionalPropertyForm`
- `NativeClassifiedAdForm`
- `NativeListingEditForm`
- `NativeEstimationRequestView`
- `NativePublicDemandForm`
- `NativeBuyerSearchForm`
- `NativeClassifiedReportSheet`

### Profils, favoris et contacts

- `ProfessionalDetailView`
- `PrivatePropertyContactForm`
- `ProfessionalMinisiteRequestForm`
- `ImportedProfessionalContactForm`
- `ImportedListingContactForm`
- `NativeFavoritesView`

### Comptes et espace complet

- `RoleEntryView`
- `LegalAcceptanceSheet`
- `ProfessionalPortalDashboardView`
- `ProfessionalPortalWebView`
- `NativeRoleDashboardView`

### Messagerie et espaces saisonniers

- `NativeProfessionalConversationView`
- `NativeHostConversationView`
- `NativeSeasonalAccommodationDetail`
- `NativeSeasonalAccommodationForm`
- `NativeSeasonalCalendarEditor`
- `NativeSeasonalRateForm`

### Services métier complémentaires

- `ProfessionalImportCenterView`
- `ReferralCenterView`
- `ReferralCandidateForm`
- `ProfessionalMiniSitePreviewView`

## Écarts encore ouverts après comparaison

- La WebView donne accès au routeur Wix et à ses règles métier; la parité SwiftUI reste partielle. Les tableaux par catalogue, formulaires, inscriptions, messages, abonnements, parrainage et rapprochements sont dans `PORTING_INVENTORY.md`.
- Comptes : les données sont côté serveur, donc la connexion avec le même compte et le même espace retrouve le même dossier entre appareils; chaque appareil garde toutefois sa session. Les systèmes particuliers, courtier, artisan/diagnostiqueur, prestataire, hébergeur/vacancier et Pro App ont des mécanismes distincts. Les parcours authentifiés inter-rôles doivent être testés sur appareils. Après une connexion Wix dans l’app, les rôles sans jeton natif ouvrent maintenant leur dashboard de site dans la même WKWebView persistante, avec les cookies Wix conservés; cela ne transforme pas ces sessions métier distinctes en un unique compte Wix Members.
- Push : l’inscription iOS du Pro App est reliée à la fiche professionnelle commune via la fonction Supabase v5. Les notifications push des autres sessions métier ne sont pas encore raccordées nativement; les e-mails continuent de dépendre des routes et services existants du site.
- Restent à compléter ou valider : parcours voyageur (favoris, réservations et messages), parrainage complet et statut des paiements, pièces jointes et détails de messagerie, livraison/retours des petites annonces, tous les e-mails et notifications, ainsi que les essais réels d’inscription, récupération de mot de passe, matching et abonnement.
- Pas de build iOS ni de parcours authentifié sur appareil dans cet environnement (`xcodebuild`, `swiftc` et `deno` indisponibles). Aucun code, page, réglage ou enregistrement Wix n’a été modifié.

## Audit détaillé du matching Wix (18 octobre 2026)

Les trois parcours demandés sont trois flux CMS distincts dans Wix. Ils ne partagent ni le même seuil, ni le même calcul, ni le même modèle d’e-mail.

| Flux Wix | Calcul et enregistrement vérifiés | Notification / e-mail du site | État natif iOS après les changements locaux de cette session |
|---|---|---|---|
| Bien d’un particulier ↔ acquéreur d’un professionnel | `privatePropertyMatchingService.ts`; admissibilité géographique stricte avec rayon, lieux secondaires et codes postaux explicites, conversion du bien en bien comparable, score existant; score minimum 60; `privateprofessionalmatchings`; mise à jour ou création par bien/acquéreur/pro/type. | Brevo Template 19 au vendeur et au professionnel propriétaire de l’acquéreur. Pas de push identifié dans ce flux. | Le tableau de bord lit les lignes existantes et affiche le bien et le professionnel; masquage synchronisé. Le formulaire natif transmet ses coordonnées et garage/piscine/annexe. Un port local cible le bien public nouvellement créé/modifié, applique le filtre de zone, le même score, le seuil 60, écrit/met à jour les matchings Wix et envoie Template 19 aux deux côtés. **Local uniquement, non déployé ni testé avec comptes réels.** Le handler Wix dépend du lien `vendorProfileId` et de profils/email valides; l’app tente d’abord le même lien puis une résolution `privateprofiles` de secours. La route publique Wix complète reste non appelée par iOS, car elle recalcule tout le stock à chaque fois et son dédoublonnage d’e-mail est mémoire seulement. |
| Recherche enregistrée d’un particulier ↔ annonce pro | `particularSearchMatchingService.ts`; score pondéré 0–100 (distance, budget, surfaces, type, pièces et équipements), annonce active, transaction compatible, seuil 80; `particularsearchmatchings`; e-mails suivis par destinataire et renvoyés si un envoi a échoué. | Brevo Template 19 vers le particulier et le professionnel; pas de push repéré dans ce service. | Le parcours natif de recherche appelle `ios-native-buyer-searches`, qui écrit le même CMS, calcule et envoie les deux e-mails avec indicateurs de livraison; masquage et recherches actives/inactives sont présents. Template 23 après publication d’un bien pro est déclenché une seule fois en tâche de fond par le serveur iOS via la route Wix du formulaire du site. La route Wix n’a pas de marqueur de livraison persistant; le déclenchement n’est donc pas réessayé si son résultat est ambigu. |
| Bien pro ↔ acquéreur pro (même pro ou réseau) | `matchingService.ts`; pré-filtres stricts transaction/type/localisation, critères obligatoires et groupes OU, puis score progressif; même propriétaire → `matchings` de type `my`; propriétaires différents → opportunité globale `opportunitesprov2` de type `reseau`. | Nouvelle opportunité : push à la création; Template 9 seulement à partir de 80 %. Matching interne : e-mail matching et push. Acceptation Wix : crée collaboration, conversation et matching accepté, puis push. La conversion par « se positionner » déclenche aussi l’e-mail matching. Le formulaire Wix ajoute également Template 23 aux recherches enregistrées après création. | Le tableau de bord liste les matchings et les conversations réseau. Changements locaux : chargement des opportunités avec le bien, les critères, l’agence source et son interlocuteur; action protégée d’acceptation qui crée collaboration, conversation, matching Wix et appelle le push Wix. Le formulaire iOS transmet maintenant coordonnées GPS et équipements garage/piscine/annexe; le moteur Wix porté localement s’exécute après création ou modification d’un bien actif, écrit les matchings internes et opportunités réseau, envoie les pushes et Template 9 aux opportunités à score ≥ 80. **Ces changements sont locaux et n’ont pas été déployés ni testés avec comptes réels.** Les autres équipements obligatoires définis par Wix ne sont pas tous présents dans le formulaire iOS; si le géocodage ne trouve pas de commune, seules les correspondances de code postal exact passent les filtres stricts. Le chemin Wix de matching interne ne résout pas de destinataire e-mail dans son handler actuel; Template 23 demeure un appel sans marqueur de livraison persistant. |

### Contrôles d’implémentation

- Vérification locale ajoutée : `npm run verify:ios-matching` couvre les filtres et scores des trois parcours de matching, les équipements des recherches enregistrées, les invariants statiques des catalogues (7 jours de priorité pour une baisse, critères visibles de l’annuaire, recherches actives paginées et attributs français), et l’accord entre les 207 routes, les 54 vues SwiftUI et `RootView.swift`. `git diff --check` passe. Le contrôle ne remplace ni la compilation iOS ni un essai authentifié.
- Les taps sur notification sont maintenant reçus par l’app, conservés si l’ouverture est à froid (seuls les identifiants de navigation sont stockés), puis dirigés vers l’onglet Menu et le rôle connu quand le payload le fournit. L’ouverture d’un fil précis reste dépendante du schéma Wix réel; aucun compte/appareil n’a permis de vérifier les payloads de production.
- Les fonctions natives de conversation professionnelle et hébergeur vérifient le compte Wix et l’appartenance de la conversation avant lecture, envoi ou marquage comme lu. L’envoi natif accepte uniquement du texte (4 000 caractères maximum); pièces jointes, livraison des alertes/e-mails et parcours de messagerie voyageur restent à valider ou à compléter.
- Les favoris de biens et petites annonces ont maintenant un cache séparé par e-mail Wix vérifié, une file locale pour les ajouts/suppressions hors ligne et une bascule vers le cache anonyme à la déconnexion. Les favoris explicitement ajoutés en mode invité dans cette version sont transférés au compte à la connexion; les favoris locaux anciens dont le compte d’origine est inconnu ne sont pas mélangés. Vérification statique seulement; les essais de changement de compte, de synchronisation multi-appareil et de reprise réseau restent nécessaires.

- Le bouton natif « Accepter cette opportunité » ne peut agir que sur une opportunité que Wix rattache au membre connecté; l’API revalide le rôle et l’appartenance avant les écritures.
- L’acceptation suit l’ordre métier Wix et est tolérante aux reprises partielles : statut, collaboration, conversation, matching, puis push secondaire. Aucun e-mail n’est ajouté à ce parcours, car le `acceptOpportunity` Wix ne le fait pas.
- Le détail d’une opportunité affiche la compatibilité, les critères acquéreur, le bien et le professionnel source; les coordonnées directes de l’autre professionnel ne sont pas exposées avant acceptation.
- Le filtre local du matching professionnel compare désormais `transactionType`/`operationType` pour achat-location et `propertyType` pour maison/appartement. Il accepte les anciennes fiches qui encodent achat/location dans `propertyType`. Le test `npm run verify:ios-matching` vérifie ces règles, le rayon géographique, les types de biens, le score propriétaire-particulier et les compteurs de la matrice. Ce correctif concerne le port local uniquement; il n’a pas été déployé sur Supabase et n’implique aucune modification Wix.
- Correctifs catalogue iOS (18 octobre 2026) : les baisses de prix immobilières gardent leur priorité sept jours comme sur le site; l’annuaire immobilier suit la visibilité Wix et classe les mandataires par `activityScore` puis par nom français. Les annuaires distincts de courtiers, artisans/diagnostiqueurs et prestataires ne sont plus fusionnés par e-mail entre métiers; les profils inscrits passent avant les imports, et les prestataires Wix (`serviceproviders`, `serviceproviders-1`) ainsi que les imports de courtiers, artisans, diagnostiqueurs et prestataires sont inclus. Le filtre de visibilité des prestataires suit le statut et la règle d’accès du site. L’onglet `Recherches` pagine `particularbuyersearches` sans afficher les coordonnées privées. Les quatre types de petites annonces restent présents et les filtres dynamiques utilisent des libellés français; les clés techniques sont retirées sans tenir compte de leur casse. L’accueil n’a qu’un accès à l’annuaire, séparé de l’explication du matching. Les contrôles statiques ne remplacent pas la comparaison des effectifs, des rangs réels et des interactions sur appareil avec les données Wix live.
- CodeMagic #60, commit `5520158`, a archivé et exporté l’IPA 1.0.15 (build 41), puis l’a téléversée sur App Store Connect sans erreur le 18 octobre 2026. Cela valide la compilation et la signature de ces changements, pas leur comportement avec un compte Wix ni leur ordre face aux données live. L’IPA n’a pas été mise en TestFlight ni publiée.
- Le scorer local de recherche enregistrée ne pénalise plus une recherche sans option d’équipement; terrasse, jardin, parking, piscine et plain-pied sont comparés à leurs champs ou caractéristiques propres. Les favoris sont isolés par e-mail de compte, Wix reste la référence lors de la synchro et les ajouts/retraits hors ligne restent en attente de reprise. La déconnexion bascule vers l’espace anonyme. Les tests locaux couvrent le matching; l’isolation SwiftUI est contrôlée statiquement en attendant compilation et essais avec deux comptes.
- Ces modifications sont **locales et non déployées**. L’absence de compilateur Swift et Deno empêche la validation de build dans cet environnement. Un test authentifié avec deux pros différents reste nécessaire avant de qualifier le flux de prêt.

## Inventaire SwiftUI complet

Les **61 déclarations `View`** de `RootView.swift` au moment de l’audit :

- `RootView`
- `NativeSeasonalStaysView`
- `SeasonalAccommodationRow`
- `CountryPickerRow`
- `NativeSeasonalAccommodationDetail`
- `NativeProfessionalsView`
- `ProfessionalDirectoryListView`
- `ProfessionalRow`
- `ProfessionalPropertyRow`
- `ProfessionalPropertyDetailView`
- `ProfessionalDetailView`
- `PrivatePropertyContactForm`
- `ProfessionalMinisiteRequestForm`
- `ImportedProfessionalContactForm`
- `ImportedListingContactForm`
- `NativeListingsView`
- `NativeCatalogContentView`
- `BuyerSearchDirectoryRow`
- `ClassifiedAdRow`
- `NativeClassifiedAdDetailView`
- `NativeClassifiedReportSheet`
- `NativeFavoritesView`
- `ListingRow`
- `ListingImage`
- `WebsiteListingDetailView`
- `ListingDetailView`
- `ListingFact`
- `HomeDashboardView`
- `CatalogPhotoCard`
- `NativePostalLocationFields`
- `NativePublicDemandForm`
- `NativeEstimationRequestView`
- `NativeBuyerSearchForm`
- `NativeListingPhotoPicker`
- `NativePrivatePropertyForm`
- `NativeClassifiedAdForm`
- `NativeProfessionalPropertyForm`
- `NativeSeasonalRateForm`
- `NativeSpacePickerView`
- `RoleEntryView`
- `LegalAcceptanceSheet`
- `ProfessionalPortalDashboardView`
- `WebsiteRoleDashboardView`
- `ProfessionalPortalWebView`
- `NativeRoleDashboardView`
- `NativeProfessionalConversationView`
- `NativeHostConversationView`
- `DashboardOverview`
- `NativeSeasonalAccommodationForm`
- `NativeSeasonalCalendarEditor`
- `ProfessionalImportCenterView`
- `ImportedListingControlRow`
- `NativeProfileShowcase`
- `NativeProfileImage`
- `WixDashboardItem`
- `ReferralCenterView`
- `ReferralCandidateRow`
- `ReferralCandidateForm`
- `ProfessionalMiniSitePreviewView`
- `NativeListingEditForm`
- `DashboardItemDetailView`
- `ListingDescriptionTranslation`
- Audit CMS Wix en lecture seule (2026-10-18) : la collection `professionnels` a 62 fiches; les règles publiques du site laissent 30 fiches complètes et visibles, puis 28 après déduplication par e-mail. La fiche de Baptiste est classée 1re par `activityScore` (2237, puis 24). Elle porte `isVisibleInDirectory = true` et `isActive = false`; le site et iOS ne doivent donc pas appliquer de filtre actif à cette collection. iOS reprend maintenant le nom/prénom dans l’affichage et la recherche, avec la société en seconde ligne. Le classement utilise `activityScore`; les `lastLoginAt` des collections de comptes et les points du programme ambassadeur (`pointsTotal`, `ambassadorpoints`) sont distincts. Les CMS locaux contiennent 5 profils éligibles (3 artisans, 2 diagnostiqueurs) dans un champ `categories` encodé en JSON; iOS lit maintenant `categories.mainCategory` pour préserver le métier réel. Wix contient aussi un profil courtier, un profil courtier historique et deux prestataires actifs, actuellement sans mise en avant. Le code local place les fiches Wix avant les imports; la présence exacte sur l’appareil dépend encore des droits de lecture anonymes et du build installé.
