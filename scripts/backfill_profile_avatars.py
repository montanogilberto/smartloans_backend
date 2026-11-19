"""Builds profile avatars for clients whose front selfie was uploaded before the
avatar existed. New uploads get one automatically (upload_id_image_connector).

Reads   {clientId}/selfies/selfie_front.jpg
Writes  {clientId}/profile/avatar.jpg        (only with --upload)

Dry run by default: avatars are written to --out locally so they can be reviewed.
Never modifies or deletes the KYC selfie.

    venv/bin/python scripts/backfill_profile_avatars.py 3371 2116 --out /tmp/avatars
    venv/bin/python scripts/backfill_profile_avatars.py --all --upload
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from dotenv import load_dotenv  # noqa: E402

load_dotenv()

from azure.core.exceptions import ResourceNotFoundError  # noqa: E402

from modules import clientFaceRecognitions as cfr  # noqa: E402
from modules.profileAvatar import AVATAR_SOURCE_SIDE, NoPersonFound, build_avatar  # noqa: E402

SOURCE_SUFFIX = f"/{cfr.BLOB_FOLDER_SELFIES}/{AVATAR_SOURCE_SIDE}.jpg"


def _clients_with_front_selfie(container) -> list:
    return sorted({b.name.split("/", 1)[0] for b in container.list_blobs()
                   if b.name.endswith(SOURCE_SUFFIX) and b.name.count("/") == 2})


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("client_ids", nargs="*")
    ap.add_argument("--all", action="store_true", help="every client with a front selfie")
    ap.add_argument("--upload", action="store_true", help="write avatar.jpg to blob storage")
    ap.add_argument("--out", default="avatars_preview", help="local folder for dry runs")
    args = ap.parse_args()

    container = cfr._blob_service_client().get_container_client(cfr._CLIENTS_CONTAINER)
    ids = _clients_with_front_selfie(container) if args.all else args.client_ids
    if not ids:
        ap.error("pass client ids or --all")
    if not args.upload:
        os.makedirs(args.out, exist_ok=True)

    done = skipped = failed = 0
    for client_id in ids:
        try:
            selfie = container.download_blob(f"{client_id}{SOURCE_SUFFIX}").readall()
            if args.upload:
                url = cfr.save_profile_avatar("", client_id, selfie)
                print(f"client {client_id}: uploaded {url}")
            else:
                path = os.path.join(args.out, f"{client_id}_avatar.jpg")
                with open(path, "wb") as f:
                    f.write(build_avatar(selfie))
                print(f"client {client_id}: wrote {path}")
            done += 1
        except ResourceNotFoundError:
            print(f"client {client_id}: no front selfie, skipped")
            skipped += 1
        except NoPersonFound:
            print(f"client {client_id}: no person found, skipped")
            skipped += 1
        except Exception as e:
            print(f"client {client_id}: failed ({type(e).__name__})")
            failed += 1
    print(f"done={done} skipped={skipped} failed={failed} upload={args.upload}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
