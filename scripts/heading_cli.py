#!/usr/bin/env python3
"""Print the sub's current heading from one of several ENU yaw sources.

Sources (all ENU, CCW from East):
    euler     /ins/sbg/ekf_euler          SBG EKF Euler angles            [default]
    ins-odom  /ins/imu/odometry           SBG EKF attitude (Odometry)
    global    /odometry/global            robot_localization global EKF
    local     /odometry/local             robot_localization local EKF
    topic:<T> any nav_msgs/Odometry topic at path T

Converts ENU yaw to:
    - ENU yaw   (CCW from East,  E=0)
    - Compass   (CW  from North, N=0)  -- standard nav heading
    - CW-East   (CW  from East,  E=0)  -- brendon's convention

Usage:
    heading_cli.py                          # stream from ekf_euler @ 2 Hz
    heading_cli.py --once                   # single reading
    heading_cli.py --source global --hz 10  # stream from /odometry/global
    heading_cli.py --source topic:/foo/odom # any nav_msgs/Odometry topic
"""

import argparse
import math
import sys
import time

import rclpy
from nav_msgs.msg import Odometry
from rclpy.qos import HistoryPolicy, QoSProfile, ReliabilityPolicy
from sbg_driver.msg import SbgEkfEuler


SOURCES = {
    "euler": ("/ins/sbg/ekf_euler", SbgEkfEuler),
    "ins-odom": ("/ins/imu/odometry", Odometry),
    "global": ("/odometry/global", Odometry),
    "local": ("/odometry/local", Odometry),
}


def yaw_from_quat(qx: float, qy: float, qz: float, qw: float) -> float:
    return math.atan2(2.0 * (qw * qz + qx * qy), 1.0 - 2.0 * (qy * qy + qz * qz))


def rpy_from_quat(
    qx: float, qy: float, qz: float, qw: float
) -> tuple[float, float, float]:
    roll = math.atan2(2.0 * (qw * qx + qy * qz), 1.0 - 2.0 * (qx * qx + qy * qy))
    sinp = max(-1.0, min(1.0, 2.0 * (qw * qy - qz * qx)))
    pitch = math.asin(sinp)
    yaw = yaw_from_quat(qx, qy, qz, qw)
    return roll, pitch, yaw


def format_line(roll_rad: float, pitch_rad: float, yaw_rad: float, valid: str) -> str:
    enu_deg = math.degrees(yaw_rad)
    compass = (90.0 - enu_deg) % 360.0
    cw_east = (-enu_deg) % 360.0
    return (
        f"compass {compass:6.1f}°  |  CW-East {cw_east:6.1f}°  |  "
        f"ENU {enu_deg:+7.1f}°  |  roll {math.degrees(roll_rad):+6.1f}°  "
        f"pitch {math.degrees(pitch_rad):+6.1f}°  [{valid}]"
    )


def resolve_source(name: str) -> tuple[str, type]:
    if name.startswith("topic:"):
        return name[len("topic:") :], Odometry
    if name not in SOURCES:
        raise SystemExit(
            f"unknown --source {name!r}; choose from {list(SOURCES)} or topic:<path>"
        )
    return SOURCES[name]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument(
        "--source",
        default="euler",
        help=f"heading source ({'|'.join(SOURCES)}|topic:<path>); default 'euler'",
    )
    parser.add_argument(
        "--once", action="store_true", help="print a single reading and exit"
    )
    parser.add_argument(
        "--hz", type=float, default=2.0, help="streaming print rate (default 2)"
    )
    args = parser.parse_args()

    topic, msg_type = resolve_source(args.source)

    rclpy.init()
    node = rclpy.create_node("heading_cli")

    qos = QoSProfile(
        reliability=ReliabilityPolicy.BEST_EFFORT,
        history=HistoryPolicy.KEEP_LAST,
        depth=1,
    )

    last_print = 0.0
    period = 0.0 if args.once else 1.0 / max(args.hz, 0.1)
    done = False

    def emit(roll: float, pitch: float, yaw: float, valid: str) -> None:
        nonlocal last_print, done
        now = time.monotonic()
        if now - last_print < period:
            return
        last_print = now
        print(format_line(roll, pitch, yaw, valid), flush=True)
        if args.once:
            done = True

    def on_euler(msg: SbgEkfEuler) -> None:
        emit(
            msg.angle.x,
            msg.angle.y,
            msg.angle.z,
            "ok" if msg.status.heading_valid else "MAG-ONLY",
        )

    def on_odom(msg: Odometry) -> None:
        q = msg.pose.pose.orientation
        roll, pitch, yaw = rpy_from_quat(q.x, q.y, q.z, q.w)
        emit(roll, pitch, yaw, topic)

    callback = on_euler if msg_type is SbgEkfEuler else on_odom
    node.create_subscription(msg_type, topic, callback, qos)

    try:
        while rclpy.ok() and not done:
            rclpy.spin_once(node, timeout_sec=0.1)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()
    return 0


if __name__ == "__main__":
    sys.exit(main())
