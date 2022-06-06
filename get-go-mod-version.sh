
echo v0.0.0-$(TZ=UTC0 git show -s --date=iso-local --date=format-local:%Y%m%d%H%M%S --format=%cd $(git rev-parse HEAD | egrep -oh '^[0-9a-z]{12}'))-$(git rev-parse HEAD | egrep -oh '^[0-9a-z]{12}')

