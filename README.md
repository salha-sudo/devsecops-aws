# Pipeline DevSecOps 100 % AWS (prêt à déployer)

Application Flask conteneurisée → CodePipeline → scans de sécurité → ECR → ECS Fargate (staging + DAST ZAP) → approbation manuelle → production (WAF).

```
GitHub ─► CodePipeline
            ├─ TestAndScan (parallèle)
            │    ├─ UnitTests      : ruff + pytest
            │    └─ SecurityScans  : Gitleaks (secrets) · Semgrep (SAST) · pip-audit + Trivy (SCA)
            │                        cfn-lint + Checkov (IaC)           ← bloque si HIGH/CRITICAL
            ├─ BuildImage          : docker build → Trivy image scan → push ECR (tags immuables, Inspector)
            ├─ Staging             : CloudFormation (ECS Fargate + ALB) → DAST OWASP ZAP
            ├─ Approval            : approbation manuelle (email SNS)
            └─ Production          : CloudFormation (2 tâches, WAF, rollback auto via circuit breaker)
Échec pipeline ─► EventBridge ─► SNS (email)
```

## Contenu

| Chemin | Rôle |
|---|---|
| `app/` | Appli Flask, tests, Dockerfile (non-root, gunicorn) |
| `buildspecs/` | `build-test`, `security`, `image`, `dast` |
| `infra/pipeline.yaml` | Pipeline, CodeBuild, KMS, S3, ECR, IAM (rôles séparés), SNS, EventBridge |
| `infra/app-stack.yaml` | Stack applicatif (staging/prod) : ALB, Fargate, WAF (prod) |
| `infra/security-baseline.yaml` | Optionnel : GuardDuty + Security Hub |
| `scripts/deploy.sh` / `cleanup.sh` | Déploiement / suppression complète |

## Prérequis

- Compte AWS, AWS CLI v2 configuré (`aws configure`), droits administrateur pour le premier déploiement
- Un compte GitHub et un **dépôt vide** (ex. `devsecops-aws`)
- Un VPC par défaut dans la région (sinon passer `VPC_ID`/`SUBNETS`)

## Déploiement (≈ 10 min)

**1. Pousser le projet sur GitHub**
```bash
cd devsecops-aws
git init -b main && git add . && git commit -m "init"
git remote add origin git@github.com:<VOTRE_USER>/devsecops-aws.git
git push -u origin main
```

**2. Déployer le pipeline**
```bash
export AWS_REGION=eu-west-3          # Paris (ou eu-south-1 Milan, etc.)
GITHUB_OWNER=<VOTRE_USER> GITHUB_REPO=devsecops-aws EMAIL=vous@mail.com \
  ./scripts/deploy.sh
```
Options : `ENABLE_BASELINE=true` (GuardDuty + Security Hub, à éviter s'ils sont déjà activés), `ENABLE_INSPECTOR=false`.

**3. Actions manuelles (une seule fois)**
1. Confirmer l'email d'abonnement SNS.
2. Console AWS → *Developer Tools → Settings → Connections* → connexion `devsecops-pipeline-gh` (statut *Pending*) → **Update pending connection** → autoriser GitHub.
3. CodePipeline → `devsecops-pipeline` → **Release change**.

**4. Suivre l'exécution** : Test/Scan → Build image → Staging + DAST → **Approve** (vous recevez un email) → Production.
L'URL de l'appli est dans CloudFormation → stack `devsecops-pipeline-app-prod` → Outputs → `AppUrl`.

## Tester le « gate » de sécurité

- Ajoutez dans `app/app.py` une fausse clé `AKIAIOSFODNN7EXAMPLE1234…` ou `eval(request.args["x"])` → le stage **SecurityScans** échoue et rien n'est déployé.
- Mettez `flask==0.12` dans `requirements.txt` → `pip-audit`/Trivy bloquent.

## Résultats de sécurité
- **Inspector** : findings ECR (Console → Inspector → Findings by container image).
- **ZAP** : rapport `zap-report.html` dans les artefacts de l'action *DAST-ZAP*.
- **GuardDuty / Security Hub** : si activés via `ENABLE_BASELINE=true`.

## Nettoyage
```bash
./scripts/cleanup.sh
```

## Coûts indicatifs
ALB (~16 $/mois chacun, ×2) + Fargate (~9 $/mois par tâche) + CodeBuild à la minute + Inspector/WAF/KMS (faibles). **Supprimez avec `cleanup.sh` après vos tests.**

## Limites volontaires de cette démo → à durcir en production
| Sujet | Démo | Production recommandée |
|---|---|---|
| Réseau | VPC par défaut, tâches en sous-réseau public | Sous-réseaux privés + VPC endpoints (ECR, S3, Logs) |
| TLS | HTTP :80 | ACM + HTTPS + redirection (+ domaine Route 53) |
| Comptes | Un seul compte | AWS Organizations : dev / staging / prod séparés, déploiement cross-account |
| IaC scan | Checkov en rapport seul (11 findings connus) | Retirer `--soft-fail` après correction ou politique d'exceptions |
| Signature d'images | Non incluse | AWS Signer (Notation) ou Cosign + vérification au déploiement |
| Garde-fous | — | SCP interdisant la désactivation de CloudTrail/GuardDuty, AWS Config rules |
| Rôle CloudFormation | Limité aux services de l'app | Ajouter un permissions boundary |
| Versions d'outils | Épinglées pour Trivy/Gitleaks ; pip non épinglé | Épingler semgrep, checkov, etc. |

## Dépannage rapide
- **Source en échec** : connexion GitHub encore *Pending* → étape 3.2.
- **Docker pull limité** : l'image de base vient d'ECR Public (pas de limite Docker Hub).
- **GuardDuty/Security Hub « already exists »** : ne pas utiliser `ENABLE_BASELINE`.
- **Trivy bloque sur une CVE sans correctif** : l'option `--ignore-unfixed` est déjà active ; sinon ajouter un `.trivyignore`.
