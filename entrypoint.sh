#!/bin/sh

set -e

if [ -z "$AWS_S3_BUCKET" ]; then
  echo "AWS_S3_BUCKET is not set. Quitting."
  exit 1
fi

if [ -z "$AWS_ACCESS_KEY_ID" ]; then
  echo "AWS_ACCESS_KEY_ID is not set. Quitting."
  exit 1
fi

if [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
  echo "AWS_SECRET_ACCESS_KEY is not set. Quitting."
  exit 1
fi

# Default to us-east-1 if AWS_REGION not set.
if [ -z "$AWS_REGION" ]; then
  AWS_REGION="us-east-1"
fi

# Override default AWS endpoint if user sets AWS_S3_ENDPOINT.
if [ -n "$AWS_S3_ENDPOINT" ]; then
  ENDPOINT_APPEND="--endpoint-url $AWS_S3_ENDPOINT"
fi

if [ "${SOURCE_DIR}" == "." -o "${SOURCE_DIR}" == "./" ]; then
  SOURCE_DIR=""
fi

if [ -n "${SOURCE_DIR}" ]; then
  SOURCE_DIR="${SOURCE_DIR%/}/"
fi

if [ "${DIST_DIR}" == "." -o "${DIST_DIR}" == "./" ]; then
  DIST_DIR=""
fi

if [ -n "${DIST_DIR}" ]; then
  DIST_DIR="${DIST_DIR%/}/"
fi

SYNCED_TAG="${AWS_S3_BUCKET}__${DIST_DIR%/}"

if [ -z $(git tag -l "${SYNCED_TAG}") ]; then
  git tag ${SYNCED_TAG} empty
  git push -f origin ${SYNCED_TAG}
fi

git fetch --depth=1 --filter=blob:none origin ${BRANCH_NAME}:${BRANCH_NAME}
git fetch --depth=1 --filter=blob:none origin tag ${SYNCED_TAG}
git symbolic-ref HEAD refs/heads/${BRANCH_NAME}
git reset -q

file_list=$(mktemp)

git diff --name-status ${SYNCED_TAG} ${BRANCH_NAME} | grep -E ".\t${SOURCE_DIR}" > ${file_list}
cat ${file_list} | grep -v ^D | awk -F'\t' '{print "git restore --source=${BRANCH_NAME} --staged --worktree \"" $2 "\""}' | sh -x

# Create a dedicated profile for this action to avoid conflicts
# with past/future actions.
# https://github.com/jakejarvis/s3-sync-action/issues/1
aws configure --profile s3-sync-action <<-EOF > /dev/null 2>&1
${AWS_ACCESS_KEY_ID}
${AWS_SECRET_ACCESS_KEY}
${AWS_REGION}
text
EOF

IFS=$'\n'

for FILENAME in $(cat ${file_list}  | grep -v ^D | awk -F'\t' '{print $2}')
do
  set -x
  aws s3 cp "${FILENAME}" "s3://${AWS_S3_BUCKET}/${DIST_DIR}${FILENAME#${SOURCE_DIR}}" \
    --profile s3-sync-action --no-progress --endpoint-url ${AWS_S3_ENDPOINT} $*
  set +x
done

for FILENAME in $(cat ${file_list} | grep ^D | awk -F'\t' '{print $2}')
do
  set -x
  aws s3 rm "s3://${AWS_S3_BUCKET}/${DIST_DIR}${FILENAME#${SOURCE_DIR}}" \
    --profile s3-sync-action --endpoint-url ${AWS_S3_ENDPOINT}
  set +x
done

rm ${file_list}

# Clear out credentials after we're done.
# We need to re-run `aws configure` with bogus input instead of
# deleting ~/.aws in case there are other credentials living there.
# https://forums.aws.amazon.com/thread.jspa?threadID=148833
aws configure --profile s3-sync-action <<-EOF > /dev/null 2>&1
null
null
null
text
EOF


git tag ${SYNCED_TAG} ${BRANCH_NAME}
git push -f origin ${SYNCED_TAG}

