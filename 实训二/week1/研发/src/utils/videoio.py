import shutil
import uuid
import subprocess
import os

import cv2
import imageio_ffmpeg


def load_video_to_cv2(input_path):
    video_stream = cv2.VideoCapture(input_path)
    fps = video_stream.get(cv2.CAP_PROP_FPS)
    full_frames = [] 
    while 1:
        still_reading, frame = video_stream.read()
        if not still_reading:
            video_stream.release()
            break 
        full_frames.append(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))
    return full_frames


def save_video_with_watermark(video, audio, save_path, watermark=False):
    video = os.path.abspath(video)
    audio = os.path.abspath(audio)
    save_path = os.path.abspath(save_path)
    temp_file = os.path.abspath(str(uuid.uuid4()) + '.mp4')
    ffmpeg_bin = os.environ.get('FFMPEG_BINARY') or imageio_ffmpeg.get_ffmpeg_exe() or 'ffmpeg'

    commands = [
        [ffmpeg_bin, '-y', '-hide_banner', '-loglevel', 'error', '-i', video, '-i', audio, '-vcodec', 'libx264', temp_file],
        [ffmpeg_bin, '-y', '-hide_banner', '-loglevel', 'error', '-i', video, '-i', audio, '-vcodec', 'copy', temp_file],
    ]

    last_error = None
    for cmd in commands:
        try:
            subprocess.run(cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            break
        except subprocess.CalledProcessError as error:
            last_error = error
    else:
        if last_error is not None and getattr(last_error, 'stderr', None):
            print(last_error.stderr.decode('utf-8', 'ignore'))
        raise last_error if last_error is not None else RuntimeError('FFmpeg mux failed')

    if not os.path.exists(temp_file):
        raise FileNotFoundError('FFmpeg did not create output file')
    shutil.move(temp_file, save_path)
