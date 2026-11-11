# Publicar Bestiary Forever en CurseForge

Todo lo que hay que pegar o subir está en esta carpeta. Crear el proyecto requiere tu cuenta de CurseForge.

## 1. Crear el proyecto

1. Entra en https://authors.curseforge.com con tu cuenta (puedes usar la de Overwolf, Google, Discord…).
2. **Create Project** → juego **World of Warcraft** → tipo **Addons**.
3. Rellena los campos:

| Campo | Qué poner |
|---|---|
| **Project name** | `Bestiary Forever` |
| **Summary** (frase corta) | `Target a creature to see its loot and drop rates. A Pokédex-style bestiary by zone, with silhouettes of the creatures you haven't found yet.` |
| **Logo / Avatar** | `curseforge/logo-400.png` (400×400) |
| **Main category** | `Quests & Leveling` |
| **Other categories** | `Map & Minimap`, `Tooltip` |
| **License** | `GNU General Public License version 3 (GPLv3)` |
| **Source code** | `https://github.com/soyelchecho/BestiaryForever` |
| **Issues** | `https://github.com/soyelchecho/BestiaryForever/issues` |
| **Website / Wiki** | `https://soyelchecho.github.io/BestiaryForever/` |

4. **Description**: cambia el editor a **Markdown** y pega todo el contenido de `curseforge/description.md`. Las imágenes se cargan desde la web del proyecto, así que no hay que subirlas aparte.
5. Guarda. CurseForge revisa los proyectos nuevos antes de publicarlos (suele tardar de horas a un par de días).

## 2. Subir el archivo

1. En el proyecto: **Files → Upload File**.
2. Archivo: el zip de la última versión en `dist/` (por ejemplo `BestiaryForever-0.2.5.zip`).
3. **Display name**: `Bestiary Forever 0.2.5`
4. **Release type**: `Beta`
5. **Game version**: marca la versión de **WoW Forever** (la que corresponde a la interfaz `16001`). Esto es lo que hace que aparezca en la sección *Forever* de la app de CurseForge.
6. **Changelog**: pega las notas de la versión (están en el release de GitHub de esa versión).

## 3. Galería (Images)

Sube estas capturas en **Images**, en este orden:

1. `docs/screenshots/zone-page.png`: página de zona del bestiario
2. `docs/screenshots/silhouettes.png`: siluetas de criaturas sin descubrir
3. `docs/screenshots/undiscovered-entry.png`: ficha de una criatura sin descubrir

Faltan capturas que expliquen mejor el addon. Cuando las hagas, ponlas en `docs/screenshots/` y súbelas también:

- La **ventana del objetivo** con un monstruo seleccionado (y otra con **+** expandido).
- La **ficha de una criatura descubierta** con su botín.
- La **pestaña Objetos** con una búsqueda hecha (por ejemplo "paño de lino") y la lista de criaturas.

## 4. Próximas versiones (opcional, automático)

Para que las siguientes versiones se suban solas a CurseForge:

1. En https://legacy.curseforge.com/account/api-tokens crea un **API token**.
2. Guárdalo como variable de entorno (no lo pegues en el chat ni en el proyecto):

   ```bash
   setx CURSEFORGE_API_TOKEN "tu_token"
   ```

3. Apunta el **Project ID** (aparece en la página del proyecto, en "About Project").

Con eso se pueden subir los zips desde un script con la API de subida de CurseForge, sin entrar en la web.
