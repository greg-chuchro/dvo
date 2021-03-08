#!/bin/bash

set -e
ARGS="$@"

if [ ! -d $PWD ]; then
    echo "ERROR: current working directory doesn't exist"
    exit 1
fi

command=$1;
if [ "$command" = '' ]; then
    dotnet
    exit 0
fi
shift
case "$command" in
    new)
        PROJECT_TYPE=$1;
        if [ "$PROJECT_TYPE" = '' ]; then
            dotnet $ARGS
            exit 0
        fi
        shift

        PROJECT_NAME=''
        while getopts "n:" option; do
            case ${option} in
                n)
                    PROJECT_NAME=$OPTARG
                    ;;
            esac
        done
        shift $((OPTIND -1))
        if [ "$PROJECT_NAME" = '' ]; then
            dotnet $ARGS
            exit 0
        fi

        PROJECT_KEBAB_NAME=$(echo $PROJECT_NAME | rgx r '(([a-z])([A-Z]))|(\B[A-Z][a-z])/$2-$3$4' | rgx r '(.*)/\L$1' | rgx r '[_ ]/-' | rgx r '\./')
        PROJECT_SNEAK_NAME=$(echo $PROJECT_NAME | rgx r '(([a-z])([A-Z]))|(\B[A-Z][a-z])/$2-$3$4' | rgx r '(.*)/\L$1' | rgx r '[- ]/_' | rgx r '\./')

        cd ~/"repos/$(git config user.name)"
        mkdir $PROJECT_KEBAB_NAME
        cd $PROJECT_KEBAB_NAME

        if [ "$PROJECT_TYPE" = 'shell' ]; then
            mkdir $PROJECT_NAME
            cd $PROJECT_NAME
            touch $PROJECT_SNEAK_NAME".sh"
            chmod +x $PROJECT_SNEAK_NAME".sh"
            cd ..
            curl https://www.toptal.com/developers/gitignore/api/linux,macos,windows,visualstudiocode > .gitignore
        else
            TEST_PROJECT_NAME=$PROJECT_NAME"Test"
            PROJECT_FILE=$PROJECT_NAME"/"$PROJECT_NAME".csproj"
            TEST_PROJECT_FILE=$TEST_PROJECT_NAME"/"$TEST_PROJECT_NAME".csproj"
            SOLUTION_FILE=$PROJECT_NAME".sln"

            dotnet new $ARGS
            dotnet new xunit -n $TEST_PROJECT_NAME
            dotnet new sln -n $PROJECT_NAME
            dotnet add $TEST_PROJECT_FILE reference $PROJECT_FILE
            dotnet sln $SOLUTION_FILE add $PROJECT_FILE $TEST_PROJECT_FILE

            curl https://www.toptal.com/developers/gitignore/api/linux,macos,windows,dotnetcore,monodevelop,visualstudio,visualstudiocode,rider > .gitignore
        fi

        curl https://raw.githubusercontent.com/github/choosealicense.com/gh-pages/_licenses/mit.txt | rgx r '---.*---\s*/' | rgx r "\[year\]/$(date +%Y)" | rgx r "\[fullname\]/$(git config user.name)" > LICENSE.txt
        touch README.md 

        git init --initial-branch=main
        git add .
        git commit -m '0.0.0'

        gh repo create $PROJECT_KEBAB_NAME
        git push --set-upstream origin main
        git switch --create dev
        git push --set-upstream origin dev
        ;;
    switch)
        git switch dev
        git pull
        git $ARGS

        CREATED_BRANCH=''
        while getopts "c:" option; do
            case ${option} in
                c)
                    CREATED_BRANCH=$OPTARG
                    ;;
            esac
        done
        shift $((OPTIND -1))
        if [ "$CREATED_BRANCH" != '' ]; then
            git push --set-upstream origin $CREATED_BRANCH
        fi
        ;;
    issue)
        ISSUE_ARGS="$@"
        ISSUE_NUMBER=$(gh issue create --title "$ISSUE_ARGS" --body '' | rgx r '.*\//')
        $0 switch -c $ISSUE_NUMBER
        ;;
    rebase)
        ISSUE_NUMBER=$(git branch --show-current)
        ISSUE_TITLE=$(gh issue view $ISSUE_NUMBER | rgx r '(.*)title:\s*([^\n]+)(.*)/$2')
        COMMITS_COUNT=$(git rev-list --count dev..$ISSUE_NUMBER)
        if [ $COMMITS_COUNT -lt 2 ]; then
            echo "nothing to rebase"
            exit 0
        fi
        git push --force
        git stash push --include-untracked --quiet
        git reset $(git merge-base dev $ISSUE_NUMBER)
        git add -A
        set +e
        git commit -m "#$ISSUE_NUMBER $ISSUE_TITLE"
        git stash pop --quiet
        set -e
        git pull --rebase origin dev
        ;;
    pr)
        $0 rebase
        git push --force
        set +e
        gh pr view
        PR_RESULT=$?
        set -e
        if [ $PR_RESULT -ne 0 ]; then
            ISSUE_NUMBER=$(git branch --show-current)
            ISSUE_TITLE=$(gh issue view $ISSUE_NUMBER | rgx r '(.*)title:\s*([^\n]+)(.*)/$2')
            gh pr create --base dev --title "#$ISSUE_NUMBER $ISSUE_TITLE" --body '' 
        fi
        ;;
    merge)
        ISSUE_NUMBER=$(git branch --show-current)
        $0 pr
        gh pr merge --squash
        git push origin --delete $ISSUE_NUMBER
        gh issue close $ISSUE_NUMBER
        git switch dev
        git branch --delete $ISSUE_NUMBER --force
        ;;
    *)
        dotnet $ARGS
        ;;
esac
