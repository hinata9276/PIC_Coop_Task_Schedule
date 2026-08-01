# PIC16F877A Cooperative Task Scheduler (Assembly)

This project demonstrates how a **cooperative task scheduler** can be implemented entirely in **PIC16F877A Assembly language**, using **Timer0** as the system tick. It is intended as an educational example to help students understand timer peripherals, interrupt-driven programming, and modular firmware architecture without relying on an RTOS.

## Overview

Instead of executing every function sequentially, the firmware uses **Timer0 interrupts** to generate a periodic system heartbeat. The Interrupt Service Routine (ISR) performs only lightweight operations:

* Reload Timer0
* Update software timing counters
* Set scheduling flags (METRO flags)
* Return immediately

The **main loop** continuously checks these scheduling flags and executes the corresponding task when its time slot arrives. Each task runs quickly, clears its flag, and returns control to the scheduler.

This design allows multiple periodic tasks to execute at different frequencies while maintaining a responsive system.

## Features

* Timer0 interrupt-based software scheduler
* Cooperative multitasking
* Multiple software timers (e.g. 4 ms, 20 ms, 40 ms, 100 ms, 400 ms, 1 s)
* Modular driver architecture
* 7-segment display driver
* Matrix keypad scanning
* ADC interface
* Binary-to-decimal conversion
* 16-bit arithmetic library (`ADD16`, `SUB16`, `MUL16`)
* Lookup tables using `RETLW`

## Firmware Architecture

```text
                Timer0 Interrupt
                       │
                       ▼
              Interrupt Service Routine
          ┌──────────────────────────────┐
          │ Save CPU Context             │
          │ Reload Timer0                │
          │ Update Software Counters     │
          │ Set METRO_xxx Flags          │
          │ Restore CPU Context          │
          └──────────────────────────────┘
                       │
                    RETFIE
                       │
                       ▼
                 Main Program Loop
                       │
        ┌──────────────┼──────────────┐
        ▼              ▼              ▼
    METRO_20MS     METRO_100MS    METRO_1S
        │              │              │
        ▼              ▼              ▼
 Display Task     Keypad Task    Background Task
```

## Project Structure

```text
├── Configuration Bits
├── Variable Declaration (CBLOCK)
├── Constants (EQU)
├── Reset & Interrupt Vectors
├── Lookup Tables
├── Interrupt Service Routine (ISR)
├── System Initialization
├── Main Scheduler Loop
├── Periodic Tasks
├── Peripheral Drivers
└── Utility Libraries
```

## Design Philosophy

This project follows several embedded software best practices:

* Keep the ISR short and deterministic.
* Perform application processing in the main loop.
* Schedule tasks using software timers instead of blocking delay loops.
* Separate hardware drivers from application logic.
* Organize code into reusable modules.
* Use lookup tables to improve efficiency and readability.

Although implemented entirely in Assembly language, the architecture resembles the core principles of a **Real-Time Operating System (RTOS)**:

* **Interrupt** → System tick
* **METRO flags** → Task events
* **Main loop** → Cooperative scheduler
* **Tasks** → Independent application modules

## Learning Objectives

This project is suitable for students learning:

* PIC Assembly Programming
* Interrupt Handling
* Timer Peripherals
* Software Timing
* Cooperative Scheduling
* Modular Embedded Software Design
* Real-Time Embedded Systems

It bridges the gap between basic Assembly programming and RTOS concepts, demonstrating how multiple independent tasks can coexist on a resource-constrained microcontroller without an operating system.

## License

This project is intended for educational purposes. Feel free to use, modify, and adapt it for teaching, learning, or personal projects.
