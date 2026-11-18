Location Simulator

Status: Development discontinued

I have discontinued development. My feasibility research did not establish a documented, reproducible way to provide system wide location input to iOS from a Mac or other device. My research was taking more time than I could justify, and I didn’t want to pursue a route that might depend on bypassing operating-system or third-party protections. The simulator was never started, and this project remains unfinished.

Project goal:
Explore whether iOS location simulation could be performed without Xcode.

Debugger:
As the feasibility-study component, I built an Xcode debugger with help from AI tools. It records Core Location updates, allows timestamped session markers—such as accessory connection and disconnection—and exports results to CSV.

In a test with an external location accessory, the debugger received updates marked isProducedByAccessory: true and isSimulatedBySoftware: false. This records the result from that test setup; it does not identify the accessory’s communication method or establish that a Mac or custom device could reproduce it.

The simulator component was not implemented.
