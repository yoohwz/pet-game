# Pet Game

Offline-first evolving pet MVP, built with **Godot 4.7.1** and GDScript. The playable portrait-first shell is 360×640 with nearest-neighbor pixel rendering, a procedural companion placeholder and a future 32×32 pet canvas target.

Run the project with `godot --editor project.godot`. Run the complete headless foundation suite with:

```sh
godot --headless --path . -s res://tests/test_runner.gd
```

The player surface supports the accepted egg, hatch, care, sleep, survival, memorial and English-only offline language loops. Developer Tools keeps raw diagnostics and the debug Time Machine separate from normal play.
