### 1.2 Radio de esquinas

- **Todo recto: radius 0 en toda la app.** Se mantiene el carácter terminal puro
  del theme actual (`BorderRadius.zero` en botones, inputs, chips, segmented
  controls, cards, sheets, dialogs, panels y navigation bar).
- No se introduce ningún token de radio. Se descarta la recomendación del skill
  de radio 10-14px en botones — decisión explícita del proyecto.
- El theme actual ya usa `BorderRadius.zero` en todos los componentes, así que
  esta sección no requiere cambios sobre lo ya implementado.
