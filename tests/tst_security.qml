import QtQuick
import QtTest
import "../Security.js" as Security
import "../Markup.js" as Markup
import "../Store.js" as Store
TestCase {
  name: "SecurityPolicy"
  function test_urls() {
    compare(Security.safeHttpUrl("https://paypal.com@evil.example"), "")
    compare(Security.safeHttpUrl("https://example.com/%250a"), "")
    compare(Security.safeHttpUrl("https://EXAMPLE.com"), "https://example.com/")
    compare(Security.safeMailtoUrl("mailto:a@example.com?attach=/etc/passwd"), "")
  }
  function test_markup_and_storage() {
    verify(Markup.render('<img src="file:///etc/passwd">').indexOf('<img') < 0)
    var row=Store.snapshot({appName:"Test",summary:"Verification",body:"Your code is 938271"},"n1",{Normal:1})
    compare(row.code,"938271")
    verify(JSON.stringify(Store.sanitiseForPersistence(row)).indexOf("938271") < 0)
  }
}
