
```sh
// Dynatrace Dashboard & Notebook Editor

ALLOW app-engine:apps:run;
ALLOW app-engine:functions:run;

ALLOW document:documents:read;
ALLOW document:documents:write;

ALLOW document:environment-shares:read;
ALLOW document:environment-shares:write;
ALLOW document:environment-shares:delete;

ALLOW document:direct-shares:read;
ALLOW document:direct-shares:write;
ALLOW document:direct-shares:delete;

ALLOW state:user-app-states:read;
ALLOW state:user-app-states:write;
ALLOW state:user-app-states:delete;
```
