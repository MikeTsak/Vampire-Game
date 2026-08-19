# Parnitha 1937

**an _Athens Through Time_ LARP story**

![Godot Engine](https://img.shields.io/badge/Godot_4-478cbf?style=for-the-badge&logo=godotengine&logoColor=white)
![Status](https://img.shields.io/badge/Status-In_Development-orange?style=for-the-badge)
![License](https://img.shields.io/badge/License-Proprietary-red?style=for-the-badge)

Created by **Michail Tsakiroglou** — [miketsak.gr](https://miketsak.gr) · [agileadvisors.gr](https://agileadvisors.gr)
Part of the **Athens Through Time** LARP universe — [attlarp.gr](https://attlarp.gr)

---

A retro-styled 3D horror game built in Godot 4. The player explores a pitch-black forest using an ultra-powerful WWI trench flashlight. The core gameplay involves hunting and trapping corrupted wildlife (deer, sheep, and their young), dragging their carcasses, and stacking them on a tarp drop-off zone to earn Drachmas (₯).

Set in the eerie Greek wilderness of Mount Parnitha in 1937, the game features heavy retro screen filters, scanlines, and an oppressive atmosphere spanning landmarks like the **"Soul Park"** and the looming **"Sanatorium of Parnitha"**.

---

## Core Features & Mechanics

* **Retro Aesthetic**: Authentic retro-style low-poly graphics featuring `Nearest` texture filtering, vertex snapping, and heavy screen-space VHS retro filters.
* **Dynamic Flashlight**: A customized WWI trench spotlight mechanic that violently cuts through the pitch-black darkness and screen filters with an organic, vintage flicker.
* **Physics-Based Loot**: Animal carcasses act as fully physical `RigidBody3D` objects that can be dynamically dragged, dropped, and stacked on the physical base camp tarp.
* **Cinematic Encounters**: Fully animated, lip-synced cutscenes introducing the mysterious "Man in the Suit" who purchases your gruesome offerings.
* **Pack Spawning System**: Dynamic enemy and mob generation that spawns interconnected packs of adults and their young across the wilderness.

---

## Controls & Debugging

**Standard Gameplay:**
* **`W` `A` `S` `D`** - Move
* **`Mouse`** - Look around
* **`Left Click`** - Fire Rifle / Interact

**Shortcuts & Debugging:**
* **Skip Intros**: Press `Space` to instantly skip cinematic intros and transitions.
* **Debug Level Skip**: Press `F10` during gameplay to instantly complete Level 1 and force the transition cinematic to Level 2.

---

## Installation & Setup

1. **Requirements**: You must have **Godot 4.x** (specifically the .NET/Mono version if running C# builds) to open and compile the project.
2. **Clone the Repository**: Download or clone the project files to your local machine.
3. **Import**: Open the Godot Project Manager, click **Import**, and select the `project.godot` file in the root directory.
4. **Play**: 
   * The main entry point to play the entire game sequentially is `res://scenes/MainMenu.tscn`.
   * To test specific levels directly, you can run `res://scenes/Level1.tscn` or `res://scenes/Level2.tscn`.

---

## Credits

* **Lead Developer & Programmer**: Michail Tsakiroglou
* **3D Modeling & Art**: [Placeholder for 3D Artists]
* **Audio Design**: [Placeholder for Audio Designers]
* **Additional Code/Collaborators**: [Placeholder for Collaborators]

---

## License

This project is licensed under a strict Proprietary License. 

Copyright (c) 2026 Michail Tsakiroglou. All Rights Reserved.

Please see the [LICENSE](LICENSE) file for more details regarding restrictions on modification, distribution, and commercial use.
