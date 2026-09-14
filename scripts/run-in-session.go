// Command run-in-session starts a command in its own process group and execs it
// without leaving a wrapper process behind. It is used by dev-session.sh so a
// terminal session can stop only the Flutter or API processes it started.
package main

import (
	"fmt"
	"os"
	"syscall"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "run-in-session: expected a command")
		os.Exit(2)
	}

	if os.Args[1] == "" || os.Args[1][0] != '/' {
		fmt.Fprintln(os.Stderr, "run-in-session: command must be an absolute path")
		os.Exit(2)
	}
	readyFile := os.Getenv("RUN_IN_SESSION_READY_FILE")
	if readyFile == "" || readyFile[0] != '/' {
		fmt.Fprintln(os.Stderr, "run-in-session: RUN_IN_SESSION_READY_FILE must be an absolute path")
		os.Exit(2)
	}
	if _, err := syscall.Setsid(); err != nil {
		fmt.Fprintf(os.Stderr, "run-in-session: could not create an owned process group: %v\n", err)
		os.Exit(1)
	}
	ready, err := os.OpenFile(readyFile, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		fmt.Fprintf(os.Stderr, "run-in-session: could not create ready file: %v\n", err)
		os.Exit(1)
	}
	if _, err := fmt.Fprintf(ready, "%d\n", os.Getpid()); err != nil {
		fmt.Fprintf(os.Stderr, "run-in-session: could not write ready file: %v\n", err)
		ready.Close()
		os.Exit(1)
	}
	if err := ready.Close(); err != nil {
		fmt.Fprintf(os.Stderr, "run-in-session: could not close ready file: %v\n", err)
		os.Exit(1)
	}
	if err := syscall.Exec(os.Args[1], os.Args[1:], os.Environ()); err != nil {
		fmt.Fprintf(os.Stderr, "run-in-session: could not start command: %v\n", err)
		os.Exit(126)
	}
}
