"""
Module: socket events
Description: python-socketio ASGI server for real-time inventory updates.

Responsibilities:
    - Handle client connect/disconnect events
    - Manage location-based rooms so clients only receive
      updates for their assigned location
    - Provide the sio instance for other modules to emit events

Dependencies:
    - python-socketio

Usage:
    # Other services emit like this:
    from app.sockets.events import sio
    await sio.emit("stock_updated", data, room=location_id)
"""

import socketio

# ── Create the Socket.IO async server ────────────────────────────
# async_mode="asgi" integrates with FastAPI's ASGI lifecycle
sio = socketio.AsyncServer(
    async_mode="asgi",
    cors_allowed_origins="*",  # restrict in production
    logger=False,
    engineio_logger=False,
)

# ASGI app to be mounted on the FastAPI application
socket_app = socketio.ASGIApp(sio)


@sio.event
async def connect(sid: str, environ: dict) -> None:
    """
    Handle new WebSocket connection.

    The client should pass its location_id as a query parameter
    so we can add it to the correct room for scoped updates.

    Args:
        sid: Socket.IO session ID for this client.
        environ: WSGI-style environ dict from the HTTP upgrade request.
    """
    # Extract location_id from query string if provided
    query_string = environ.get("QUERY_STRING", "")
    params = dict(
        pair.split("=") for pair in query_string.split("&") if "=" in pair
    )
    location_id = params.get("location_id")

    if location_id:
        # Join the location-specific room
        sio.enter_room(sid, location_id)
        await sio.save_session(sid, {"location_id": location_id})

    print(f"[Socket.IO] Client connected: {sid}, location: {location_id}")


@sio.event
async def disconnect(sid: str) -> None:
    """
    Handle client disconnection.

    Rooms are automatically cleaned up by Socket.IO on disconnect.

    Args:
        sid: Socket.IO session ID for the disconnecting client.
    """
    print(f"[Socket.IO] Client disconnected: {sid}")


@sio.event
async def join_location(sid: str, data: dict) -> None:
    """
    Allow a client to switch location rooms dynamically.

    The client emits this event when the user changes their
    active location in the app.

    Args:
        sid: Socket.IO session ID.
        data: Dict with "location_id" key.
    """
    location_id = data.get("location_id")
    if not location_id:
        return

    # Leave previous room if any
    session = await sio.get_session(sid)
    old_location = session.get("location_id") if session else None
    if old_location:
        sio.leave_room(sid, old_location)

    # Join new room
    sio.enter_room(sid, location_id)
    await sio.save_session(sid, {"location_id": location_id})
