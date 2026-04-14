# Redmine Merge Issues

Plugin Redmine permettant de **fusionner des tickets** : déplace tout le contenu d'un ticket source (commentaires, temps passé, pièces jointes, sous-tickets, liens, observateurs) dans un ticket de destination, puis supprime le ticket source.

## Fonctionnalités

| Élément | Comportement |
|---|---|
| **Description source** | Convertie en commentaire (journal) dans le ticket de destination |
| **Commentaires / journaux** | Déplacés vers le ticket de destination |
| **Temps passé** | Déplacé vers le ticket de destination |
| **Pièces jointes** | Déplacées vers le ticket de destination |
| **Sous-tickets** | Rattachés au ticket de destination |
| **Liens entre tickets** | Déplacés (doublons ignorés, auto-références évitées) |
| **Observateurs** | Fusionnés dans le ticket de destination |
| **Paramètres destination** | Inchangés (description, assigné, statut, etc.) |
| **Note de fusion** | Ajoutée automatiquement dans le ticket de destination |

## Installation

```bash
# 1. Copier le plugin dans le dossier plugins de Redmine
cp -r redmine_merge_issues /path/to/redmine/plugins/

# 2. Installer les dépendances (si nécessaire)
cd /path/to/redmine
bundle install
```

## Configuration des permissions

1. Aller dans **Administration → Rôles et permissions**
2. Pour chaque rôle devant pouvoir fusionner des tickets, cocher **"Fusionner des tickets"** dans la section *Suivi des demandes*

## Utilisation

1. Ouvrir un ticket (ticket source à supprimer)
2. Cliquer sur le lien **⊕ Fusionner** dans la barre d'actions du ticket
3. Dans la modale, saisir le numéro du ticket de destination
   - Un aperçu en temps réel affiche le titre et le projet du ticket trouvé
4. Cliquer sur **Fusionner**
5. Le ticket source est supprimé, tout son contenu est déplacé dans le ticket de destination

## Compatibilité

- Redmine ≥ 5.0
- Ruby ≥ 3.0

## Structure du plugin

```
redmine_merge_issues/
├── init.rb                                  # Déclaration du plugin
├── config/
│   ├── routes.rb                            # Routes : /issues/:id/merge
│   └── locales/
│       ├── fr.yml                           # Traductions françaises
│       └── en.yml                           # Traductions anglaises
├── app/
│   ├── controllers/
│   │   └── merge_issues_controller.rb      # Logique de fusion
│   ├── helpers/
│   │   └── merge_issues_helper.rb
│   └── views/
│       └── merge_issues/
│           ├── _merge_link.html.erb         # Lien dans la page ticket (hook)
│           └── new.html.erb                 # Modale de fusion
└── lib/
    ├── redmine_merge_issues.rb
    └── redmine_merge_issues/
        └── hooks.rb                         # Hook de vue Redmine
```
