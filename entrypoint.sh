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


git fetch --depth=1 --filter=blob:none origin h.almutawa-patch-1:h.almutawa-patch-1
git fetch --depth=1 --filter=blob:none origin live:live
git symbolic-ref HEAD refs/heads/h.almutawa-patch-1
git reset -q

file_list=$(mktemp)

git diff --name-status origin/live h.almutawa-patch-1 | grep -E ".\t${SOURCE_DIR}" > ${file_list}
cat ${file_list} | grep -v ^D | awk -F'\t' '{print "git restore --source=h.almutawa-patch-1 --staged --worktree \"" $2 "\""}' | sh -x

# Create a dedicated profile for this action to avoid conflicts
# with past/future actions.
# https://github.com/jakejarvis/s3-sync-action/issues/1
aws configure --profile s3-sync-action <<-EOF > /dev/null 2>&1
${AWS_ACCESS_KEY_ID}
${AWS_SECRET_ACCESS_KEY}
${AWS_REGION}
text
EOF

for FILENAME in $(cat ${file_list} | awk '{print -F'\t' "\"" $2 "\""}')
do
  set -x
  aws s3 sync "${SOURCE_DIR%/}" "s3://${AWS_S3_BUCKET}/${DEST_DIR}/" \
    --exclude='*' --include="${FILENAME}" \
    --profile s3-sync-action \
    --no-progress \
    ${ENDPOINT_APPEND} $*
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
