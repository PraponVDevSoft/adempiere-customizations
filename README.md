# ADempiere Customizations

Template repository for organization-specific ADempiere customizations.
Fork this repository to add your own Java patches, library dependencies, and localization modules.

---

## Repository structure

```
adempiere-customizations/
├── base/
│   ├── src/main/java/     ← Your organization's Java classes go here
│   │                         Override or extend ADempiere models, processes, validators, etc.
│   │                         Use standard ADempiere package names:
│   │                         org/compiere/model/, org/adempiere/*, etc.
│   └── build.gradle       ← Generic io.github.adempiere library dependencies
│                             (applicable to all implementors using this stack)
├── patches/
│   └── build.gradle       ← Your organization's specific library dependencies
│                             (localization JARs, industry-specific libraries, etc.)
└── [additional modules]/  ← Optional: add further patch modules (see below)
```

---

## How to add Java customizations (`base/src/`)

Add your Java source files under `base/src/main/java/`.
Use standard ADempiere package names — the module name `base` is a Gradle build identifier
only and does not affect Java package or class naming.

---

## How to add organization-specific library dependencies (`patches/`)

Declare your organization's proprietary or localization libraries in `patches/build.gradle`
under the `dependencies` block. A commented example is provided there.

---

## How to add a patch module

For larger or logically separate patches, add a dedicated module.
Example: adding a patch for `org.spin.loan_management`.

`settings.gradle` already includes loan management as an example:
```gradle
include (':' + rootProject.name + '.investment-and-loan')
project (':' + rootProject.name + '.investment-and-loan').projectDir = file('investment-and-loan')
```

Steps:
- Add a subfolder named `investment-and-loan`
- Add `api project(':adempiere-customizations.investment-and-loan')` in the root `build.gradle`
  below `api project(':adempiere-customizations.base')`
- Inside the folder add a `build.gradle` modelled on `base/build.gradle`
- Change `def packageName = "base"` to `def packageName = "investment-and-loan"`
- Add a `src/main/java` folder and place your patch classes there

---

## Local build setup

Add to `~/.gradle/gradle.properties`:

```properties
deployUsername=YOUR_GITHUB_USERNAME
deployToken=YOUR_GITHUB_PAT_WITH_READ_PACKAGES_SCOPE
```

Build:
```bash
gradle clean build
```

---

## Repository secrets

### General
- `DEPLOY_PUBLISH_GROUP`: Group to publish. Default: `io.github.adempiere`.

### GitHub Packages (required for all)

Required whether you use this repo as-is or as a fork.

- `DEPLOY_PUBLISH_GITHUB_URL`: Publish URL. Default: `https://maven.pkg.github.com/adempiere/adempiere-customizations`.
  Change this to your own org/repo if you are publishing from a fork.
- `DEPLOY_REPOSITORY`: Maven repository URL for downloading packages. Default: `https://maven.pkg.github.com/adempiere/adempiere-customizations`.
- `DEPLOY_USER`: GitHub username with write access to the package repository.
- `DEPLOY_TOKEN`: GitHub classic PAT with `write:packages` scope for the above user.

### Maven Central / Sonatype (adempiere org only)

The adempiere org publishes releases to Maven Central under the group `io.github.adempiere`.
This is the standard publication policy for this repository.
Implementors publishing from a fork do **not** need these secrets — GitHub Packages is sufficient.

- `DEPLOY_PUBLISH_SONATYPE_URL`: Sonatype staging URL. Default: `https://s01.oss.sonatype.org/service/local/staging/deploy/maven2/`.
- `PGP_PASSPHRASE`: Passphrase for the GPG signing key.
- `PGP_SECRET`: GPG private key (base64-encoded).
- `OSSRH_USERNAME`: Sonatype username.
- `OSSRH_TOKEN`: Sonatype token.

---

## Integration with adempiere-ui-gateway

Releasing a new version of this repository triggers a chain of dependent
container releases that ends with updated Docker image tags in
`adempiere-ui-gateway`. Template scripts that automate this chain are provided
in `scripts/templates/`.

See [docs/customization-workflow.md](docs/customization-workflow.md) for the
full dependency diagram, step-by-step propagation description, required
permissions, and script setup instructions.
