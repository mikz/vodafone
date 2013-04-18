# Vodafone PDF invoice parser

I needed to extract values from all invoices got from Vodafone Czech.
So this script parses the PDF and outputs the values as csv.
Of course it can be updated to do whatever report you need.


## How to use it?

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

