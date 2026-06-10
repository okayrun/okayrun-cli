# Spec: SYN-89 - Restructure okay run payload stream via SSH and add okay exec

This specification defines the transition of the connection architecture so that `okay run` streams the container's entrypoint/CMD natively over SSH, and introduces `okay exec` to allow developers to spawn out-of-band interactive shell sessions inside running VMs.

## Requirements

1. **SSHD Boot-only Lifecycle:**
   - Update `okayrun-agent` guest initialization templates so that `/sbin/init` only configures network interfaces and starts Dropbear SSHD on boot. It should not execute the container's entrypoint directly in the background. Instead, it blocks/sleeps to keep the VM alive.

2. **`okay run` over SSH Session Channel:**
   - Refactor `okayrun-cli` and `okayrun-agent` so that the CLI client establishes the SSH connection first, fetches the container's metadata (Entrypoint + CMD) from the Control Plane, and executes the entrypoint via a dedicated SSH session channel (`session.Run` or `session.Shell`).
   - Standard input, output, and error streams of the container process are natively piped over this SSH channel back to the user's local terminal.

3. **`okay exec` Implementation:**
   - Introduce `okay exec <session_id> [command]` inside the `okayrun-cli` command suite.
   - It dials the same active VM session on TCP port 22 via the agent, multiplexing a second concurrent SSH session channel executing the requested debug shell or command.

4. **Exit Status & Signal Propagation:**
   - Propagate standard SSH signal packets (`SIGINT` on `Ctrl+C`) directly to the remote container process.
   - Propagate the remote container's exit code back to the local CLI client upon process termination.

## Implementation Details

### Database / Control Plane
- Add text columns `entrypoint` and `cmd` to the `sessions` table in SQLite (stored as JSON arrays).
- Provide a datastore method `UpdateSessionMetadata` to persist parsed container metadata.
- Expose `Entrypoint` and `Cmd` fields on the `Session` struct returned to the CLI client.
- Support multiple active websocket console connections concurrently and only terminate the VM session when all websocket connections are closed.

### Agent
- Modify `configureOCIInit` in `vm.go` to remove direct entrypoint execution and instead run Dropbear in the background, printing `===OKAYRUN_READY===` and blocking.
- Return container entrypoint/cmd metadata in the `Provision` response back to the Control Plane.

### CLI
- Implement `okay exec <session_id> [command]` in the command suite.
- Update `ConnectInteractive` to execute the container's Entrypoint + CMD via SSH `session.Run` when populated, otherwise falling back to a shell.
- Propagate remote exit codes on session termination.
