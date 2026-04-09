<div align="center">
  <h1>CABSFlight</h1>
  <p><b>An experimental, fluid transit interface for the OSU CABS system.</b></p>

  <p>
    <img src="https://img.shields.io/badge/Status-Under%20Construction-FF9900?style=for-the-badge" alt="Under Construction">
    <img src="https://img.shields.io/badge/Focus-UI%2FUX%20Design-FF2D55?style=for-the-badge" alt="UI/UX">
  </p>
</div>

> **Disclaimer:** This is a personal passion project created purely out of interest in UI/UX design and iOS development. It is **not** affiliated with, endorsed by, or connected to The Ohio State University or the official Campus Area Bus Service (CABS).

## Overview

CABSFlight is an unofficial, real-time campus transit tracker designed with a relentless focus on aesthetics and user experience. 

Currently in its very early stages of development, the project explores how modern Apple design languages—specifically the "Liquid Glass" aesthetic—can transform a standard utility app into a premium, tactile experience. It aims to solve the friction of inaccurate bus ETAs while delivering an uncompromising, fluid interface.

---

## Showcase

*Note: The project is still heavily under construction. The screenshots below represent early UI/UX prototypes.*

<div align="center">
  <table>
    <tr>
      <td align="center"><b>Onboarding Experience</b></td>
      <td align="center"><b>Dynamic Backgrounds</b></td>
      <td align="center"><b>In-App Interface</b></td>
    </tr>
    <tr>
      <td><img src="https://fusiondrive.github.io/assets/CABSF/boarding1.png" alt="Onboarding 1" width="250"></td>
      <td><img src="https://fusiondrive.github.io/assets/CABSF/boarding2.png" alt="Onboarding 2" width="250"></td>
      <td><img src="https://fusiondrive.github.io/assets/CABSF/inapp.png" alt="In-App View" width="250"></td>
    </tr>
  </table>
</div>

---

## Design & Experience Focus

Rather than focusing solely on backend data, this project is an exercise in frontend interaction design:

* **Liquid Glass Aesthetic:** Utilizing modern iOS materials to create a sense of depth. Floating panels and route chips realistically refract the underlying map, making the UI feel like physical glass.
* **Algorithmic User Experience:** Exploring a custom prediction model that factors in stop dwell times and campus traffic, preventing the infinite "1 minute away" problem when buses are holding at terminals.
* **Physics-Based Interactions:** Implementing seamless state transitions and tactile feedback so the interface feels organic and responsive to touch.

---

## Development Status & To-Do List

This project is currently in the **Initial Prototype Phase**. Core UI components are being built and tested before full data integration.

- [x] Initial MapKit setup and custom map styling
- [x] "Liquid Glass" UI architecture and layout
- [x] Onboarding flow with Mesh Gradient backgrounds
- [ ] **Live Activities & Dynamic Island:** Context-aware countdowns notifying users exactly when to leave for the bus stop based on their real-time walking distance.
- [ ] **Predictive Scheduling:** Glanceable upcoming bus itineraries and departure previews to reduce wait anxiety.
- [ ] **Multi-Route Orchestration:** Seamless UX flows for handling complex transfers and multi-bus campus commutes.
- [ ] **Smooth Movement Interpolation:** Physics-based vehicle animations to eliminate jarring map-marker jumps.

---

## Tech Stack

* **Platform:** iOS (Swift, SwiftUI)
* **Frameworks:** MapKit
* **Design Tools:** Figma, Apple HIG

---

## About the Developer

Designed and engineered by **Steve Wang**. 

I am a Senior Electrical and Computer Engineering student at The Ohio State University, specializing in bridging the gap between technical engineering and high-fidelity visual design.

* **Portfolio:** [fusiondrive.github.io](https://fusiondrive.github.io)
* **GitHub:** [@fusiondrive](https://github.com/fusiondrive)
