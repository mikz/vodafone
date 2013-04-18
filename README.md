# Vodafone PDF invoice parser

I needed to extract values from all invoices got from Vodafone Czech.
So this script parses the PDF and outputs the values as csv.
Of course it can be updated to do whatever report you need.


# Is this any good?
Sure! If you want to transfer you number to different operator you need data
to back up your decision. This provides the data for you.
Make a nice spreadsheet with all the variants and you are good!

If you have detailed invoice with all the calls you made, this can also parse it.
But there is no reporter for this kind of invoice.

## How to use it?

* `git submodule add pdf-reader https://github.com/mikz/pdf-reader.git` (adds some aliases needed by vodafone pdf)
* `bundle install`
* `./parse-pdf.rb invoices/*.pdf`
* profit!

## Questions
If you want to hack your own reporter, just ask me and I can help!
The code is a bit mess right now :)

All you should need is to create new method like `group_report`,
`inline_report` and new `Report` class.
Then add statement to switch on the bottom and you are good to go.


## Contributions

All is welcomed!

