# Deployment note

Deployment to demo website via Static Web App 
.

To deploy:
- install node package manager
- create .env file based on .env.example
- add deployment token from created Static Web App
- deploy using the following command:
  - preview: `npx --yes @azure/static-web-apps-cli@latest deploy .\build --env preview`
  - production: `npx --yes @azure/static-web-apps-cli@latest deploy .\build --env production`
