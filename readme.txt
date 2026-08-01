## Program Overview

This program demonstrates a **cooperative task scheduler** implemented entirely in PIC Assembly language. Instead of executing all functions sequentially, the firmware uses **Timer0** to generate periodic interrupts that serve as a system heartbeat. The interrupt service routine (ISR) performs only lightweight operations: it reloads the timer, updates software counters, and sets timing flags (METRO flags) when predefined intervals have elapsed.

The **main loop** continuously checks these timing flags and executes the corresponding task when a flag is set. Each task performs its operation quickly, clears its own flag, and returns immediately, allowing other scheduled tasks to run. This design avoids long blocking delays and enables multiple periodic functions to share the processor efficiently.

### Program Structure

* **Configuration & Variable Declaration**

  * Configure the microcontroller, oscillator, peripherals, and declare global variables.

* **Lookup Tables**

  * Store constant data such as 7-segment display patterns and keypad lookup tables using `RETLW` instructions for compact and efficient access.

* **Interrupt Service Routine (ISR)**

  * Save CPU context.
  * Reload Timer0.
  * Update software timing counters.
  * Set METRO flags when each timing interval expires.
  * Restore CPU context and return immediately.

* **Main Loop (Scheduler)**

  * Continuously polls the METRO flags.
  * Executes only the tasks whose flags are set.
  * Clears the flag after completing each task.

* **Application Tasks**

  * Each task has a dedicated execution period (e.g., 20 ms, 40 ms, 100 ms, 400 ms, 1 s).
  * Examples include LED control, keypad scanning, display refresh, and counter updates.

* **Driver & Utility Routines**

  * Reusable modules such as ADC, keypad scanning, 7-segment display, binary-to-decimal conversion, arithmetic functions (`ADD16`, `SUB16`, `MUL16`), and delay routines.

### Design Philosophy

This program demonstrates several good embedded software practices:

* Keep the interrupt service routine **short and deterministic**.
* Perform application processing in the **main loop**, not inside the ISR.
* Divide the program into **small, modular tasks** with a single responsibility.
* Schedule tasks using **software timers** instead of blocking delay loops.
* Organize code into reusable libraries to improve readability, debugging, and maintenance.

Although simple, this architecture resembles the design philosophy of a **Real-Time Operating System (RTOS)**. The ISR acts as the system timer (tick), while the main loop behaves as a cooperative scheduler that dispatches periodic tasks based on software timing events.
