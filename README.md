># PROJECT AV3D (Acoustic Levitation Volumetric Display)

### Basic intro

Basic Intro:
AV3D or Avid as is our nickname, is an acoustophoretic volumetric display. It will be able to display 3D objects using acoustic radiation forces to levitate and rapidly move a small physical particle. We utilize a fast computer and synchronized LEDs to iterate a Persistence of Vision effect, making the fast bead appear 3D.

This is our Hackclub **Fallen** project, that will hopefully let *us* go to **Shenzhen**!

---

## Disclaimer
>Before we start, this project was inspired by DanFoisy's [VATP project](https://github.com/danfoisy/vdatp), all material created thereafter is original to the [team](#Team). (they are here in the [credits](#Credits))

---

> ## Table of Contents
>- [AV3D ("Avid") – a levitating 3D display](#PROJECT-AV3D-(Acoustic-Levitation-Volumetric-Display))
>   - [Why we made it](#why-we-made-it)
>   - [What even is our project?](#what-even-is-our-project) ![thinking monkey](https://s.yimg.com/lo/mysterio/api/9b1e38019f04650961897c1e01fb28e2516c81eb4057ed7c00ebdf5700ba8f04/lightyear_networkapi/resizefill_w720_h480%3Bquality_80%3Bformat_webp/https%3A%2F%2Fmedia.zenfs.com%2Fen%2Fknow_your_meme_909%2Fc5f02a6432ec9dffe31ad021803be151)
>   - [How to use our project](#how-to-use-our-project)
>   - [Screenshots](#screenshots)
>       - [Full 3D assembly](#full-3d-assembly)
>       - [PCB](#pcb)
>       - [Board map](#board-map)
>       - [Schematic](#schematic)
>       - [3D render](#3d-render)
>       - [Final product (build submission)](#final-product-build-submission)
> - [How the important parts work](#how-the-important-parts-work)
> - [What is in our repo?](#whats-in-this-repo)
> - [Screenshots](#screenshots)
> - [Basic Specs](#basic-specs)
> -  [Team](#team)
> - [Credits](#Credits)

---


### Why we made it

We made the project since this is our first time doing a project like this, we had a 4 person team and wanted to make something that would be adequate for our team’s skill level, but wouldn't be overly challenging for all of us. We were looking on though youtube, and our team first saw the video posted by DanFoisy, we thought that this was very intresting and wondered if us, as students could possibly make something like this. However, most builds that we found used either insanly expensive or obselete and parts that has not been manufactured, so we designed our own version around parts we could actually buy online.

----

## What even is our project?
AV3D is an ultra sound powered, 3d visual display made from two boards facing each other that is around 135 mm apart. Each board has 144 small ultrasonic transducers, arranged in a 12 × 12 grid. (288 total transducers).

#### Making the bead float

If you shift the timing (or phase) of each transducer, the sound wave energy that the transducers gives our makes a small trap, which is when two boards with transducers on the top and bottom compacts loud sound in a single spot, into a small pocket that bends gravity so the polystyrene bead can float inside of it. The two boards are delayed by an extra half cycle (16 steps), which means that at the target, the waves from the bottom board and the top board arrive exactly half a cycle apart, so they cancel and creates a node or an quiet spot which the bead can float in.

#### How our project uses Persistence of Vision

If the bead starts moving at a fast enough pace, then your eyes and brain start to blend together images, which called persistence of vision. AV3D does this when the bead goes all the way round a shape in about 0.1 seconds (very very fast), and when the LEDs light it, you see the whole shape at once, which creates an illusion of an 3d image all while the bead floats in the pocket that the transducers have created.

##### TLDR: Transducers make small pocket using sound waves that trap the bead in the middle. If the bead is illuminated by an LED moves fast enough, your eyes blur its path into a solid shape using the persistence of vision.

---


## How to use OUR project

From the bead trapped in the pocket made by the transducers with those sound waves, we can use our project to see 3D shapes, letters, numbers, and produce audible sound and visual diagrams that someone could theoretically touch. (highly advised that you don't!!!)

#### Project start up

>1. Flash the two Tang Nanos and set up the Raspberry Pi.
>2. turn on the power supply and then the Raspberry Pi
>3. Run cli.py on the Raspberry Pi
>4. Press home so the trap holds still which gives enough space for the bead.
>5. Place one single 2-3mm polystyrene foam bead in the middle with tweezers, then let go once it starts floating.
>6. Slowly move the bead using computer to see if the trap is following our commands.
>7. Load wanted shape, start to slowly move the bead and then slowly give the polystyrene bead more speed until it speeds up.
>8. Change color of the bead with LED controls.
>9. Press “all off”, then turn off the power supplies.

>

---


## How important parts work

How the work is split:

- **Raspberry Pi Zero 2 W:**  The Raspberry pi works out how each transducer should be timed in python, as well as the phase of every transducer for each point in a shape and sends the result to both boards over SPI.
- **Tang Nano 20K FPGA:** (one on each board) The Tang Nano 20K FPGA stores the shape and plays it back with exact timing. The top board sends sync signals to the bottom board so they stay in step.
- **Manorshi MSO-P1040H07T Transducers:** 144 of them on each board (288 total) create the sound waves that make the pocket where the polystyrene bead can fit in.
- **2-3mm polysterne bead:** floats in the air and moves along the outline of the board very fast, illuminated by 3 LEDs to create shapes using persistence of vision.
- **74AHC595 shift registers:** 18 shift registers per board, (36 total) they turn the FPGA's signals into 144 separate channels.
- **TC4428A drivers:** (one per transducer) switch 12 V to drive each transducer, these drivers make the sound loud enough to trap the polystyrene bead.
- **RGB LEDs:** 3 RGB LEDS on the bottom board that lights up the bead.


---



# Screenshots

### Full 3D assembly
![3D assembly]()
  TBD

### PCB
| Front (transducer side) | Back (driver side) |
| --- | --- |
| ![PCB front](https://media.discordapp.net/attachments/1565561822726332416/1571270647471145042/Screenshot_2026-11-14_at_2.08.30_PM.png?ex=6afa1f53&is=6af8cdd3&hm=6626a6bbd38433688cbfcf31b51809ddb0e475d49872c4cd565328772fe5235f&quality=lossless) | ![PCB back](https://media.discordapp.net/attachments/1565561822726332416/1571270647471145042/Screenshot_2026-11-14_at_2.08.30_PM.png?ex=6afa1f53&is=6af8cdd3&hm=6626a6bbd38433688cbfcf31b51809ddb0e475d49872c4cd565328772fe5235f&quality=lossless) |

### Board map
What each part of the board does:

![Board map]()
tbd

### Schematic
![Schematic]()

tbd
Full schematic: [e]()


### 3D render
![3D render]()
tbd

---


## Final product (build submission)

### Demo video

Coming soon: [link to demo video]()

### Final product

Coming soon: photos of the finished build.
>- ![Front](images/render.png)


>- ![Back](images/render.png)

>- ![Left side](images/render.png)

>- ![Right side](images/render.png)

>- ![Top Board](images/render.png)

>- ![Bottom PCB board](images/render.png)

>- ![Project in Operation](images/render.png)

>- ![3D render](images/render.png)



---




## Basic specs (Improtant Parts)

| **Sound**| |
| ---| --- |
|Transducer |Manorshi MSO-P1Z1040DH07T 10 mm 40 kHz transducers × 330 (288 used) |
|  Drivers |TC4428A drivers × 288 (PCB) |

|**Control**  | |
| ---| --- |
| Controller | Raspberry Pi Zero 2 W (SPI to the boards) |
| FPGAs | Tang Nano 20K (2 per board) |
| Shift Register|TI SN74AHC595 (on the PCB) |

| **Power**| |
| ---| --- |
|Power supply |Mean Well GST160A12-R7B, 12 V 11.5 A adapter × 1  |
| Fuse|5 A slow-blow Fuse|

| **Lighting**| |
|--- |--- |
|LEDS |6W 3 pin RGB LEDs |

| **USE**| |
|--- |--- |
|Foam beads | Polystyrene foam beads, 1–3 mm|

---

## What's in this repo

| Folder | What's inside |
|---|---|
| `Hardware/kicad/` | KiCad PCB files, Gerbers and assembly files |
| `cad/` | CAD files for the frame of AV3D |
| `Firmware/fpga` | Verilog code for the Tang Nano 20K |
| `Firmware/pi` | Python code for the Raspberry Pi |
| `docs/` | Design notes and channel map |
| `BOM.csv` | parts list with prices |

---
## Safety notices

>- **Keep your head out of the gap between the boards**
>- **Keep sessions short**
>- **Unplug the power before touching the boards**
>- **Do not stick your fingers into the box when in an active demo**
>- **Don't put your ears near the array**
>- **Keep pets out of the room due to transducers**
>- **Avoid touching static things to npt damage the chips of the nano or the raspberry Pi**
>- **Do not touch the boards while they're running**
>- **if something smells off, or something starts smoking, turn them off**

----
## Team
- [CanadianOrca](https://github.com/CanadianOrca) (Jason Cui) – Primary Lead, Firmware
- [awau2011](https://github.com/awau2011) (Andre Au) – Secondary Lead, CAD Design
- [harishmaharaja24](https://github.com/harishmaharaja24) (Harish Maharaja) – PCB Design, Electronics
- [Salestics](https://github.com/Salestics) (Lucas Huang) –  Planning, Administration

---
## Credits
- Dan Foisy's [VDATP](https://github.com/danfoisy/vdatp), the open-source build that got us started.
- Hirayama et al., "A volumetric display for visual, tactile and audio presentation using acoustic trapping", *Nature* (2019), the research paper we used to research about the idea of AV3D
- Hack Club, for running Fallen 💖.
