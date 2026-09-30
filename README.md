# SnoozeFest

## Problem

My son has had trouble sleeping for as long as I can remember. Over the years, we've tried many interventions to help him sleep better, and we've kept a log the whole time: how long he slept, when he woke up, and what we changed. For a long time that log lived in simple notes, which made it hard to answer the question that mattered most: did a change actually help, or were we just seeing an ordinary run of good or bad nights?

I wanted a simple iPhone app that would let me log each night's sleep in a few seconds, record when we start, stop, or change something, and then compare the nights before and after each change. Most sleep apps I found are designed for adults with wearables and focus on sleep stages and scores, not on whether a specific change helped.

That's why I built SnoozeFest.

SnoozeFest lets parents log how long their child slept and how often they woke up, and record interventions along the way. It shows everything on one chart and compares the nights before and after each intervention using standard statistical tests. For each intervention, it tells you whether there is strong evidence of a difference, whether the difference is still just suggestive, or whether there isn't enough data yet. It also estimates how many more nights you would need to log to find out.

SnoozeFest is a tracking tool, not medical advice. Always discuss changes with your child's doctor.

## Install On Your iPhone

You need a Mac, an iPhone, and a USB cable to install SnoozeFest on your iPhone. If you need help, I suggest asking an AI assistant to walk you through it step by step. Just copy and paste this prompt:

```
I want to install an iPhone app from GitHub onto my own iPhone using Xcode. Please guide me one step at a time and wait for me to confirm each step before continuing.

The app is called SnoozeFest. I need help with:
- installing Xcode
- downloading the GitHub repository (https://github.com/guidolang/snoozefest)
- opening `SnoozeFest.xcodeproj` in Xcode
- selecting my iPhone as the run destination
- setting up Signing & Capabilities with my Apple ID (selecting my own team)
- changing the bundle identifier if necessary
- running the app on my iPhone
- enabling Developer Mode or trusting the developer account if iOS asks

Also explain that without an active Apple Developer Program membership, the app will need to be reinstalled after 7 days.
```

## Development

Build:

```sh
xcodebuild build -project SnoozeFest.xcodeproj -scheme SnoozeFest -destination 'platform=iOS Simulator,name=iPhone 17'
```

Test:

```sh
xcodebuild test -project SnoozeFest.xcodeproj -scheme SnoozeFest -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Privacy

SnoozeFest does not collect or transmit personal data. Sleep logs and interventions are stored locally on the device. They only leave it if you export them as a CSV file from Settings.

## Support

For support, bug reports, or feature requests, please open a [GitHub issue](https://github.com/guidolang/snoozefest/issues).
