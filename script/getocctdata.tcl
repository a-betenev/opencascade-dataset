# This script checks OCCT tests results looking for tests that have status
# SKIPPED due to lack of data file,
# tries to identify corresponding issues in OCCT Mantis bug tracker,
# and if issue is accessible and has attachments,
# downloads these attachments and reports relevant tests and issues.
#
# This allows recovering data files that are not included in OCCT
# public dataset but still available in Mantis, to enable relevant tests.
#
# For downloading the files, a user account in OCCT bug tracker is needed.
#
# Before running this script, 
# - set current directory to folder where results of tests execution are stored.
# - set environment variable MANTIS_STRING_COOKIE equal to value of same-named
#   cookie in your browser, created when you log in to OCCT bug tracker,
#   https://tracker.dev.opencascade.org
#
# The attachments saved in the current directory (checked results folder). 

# path to directory containing results of tests execution
set path [pwd]
if {![file exists $path/tests.log]} {
  puts "Error: file tests.log not found! Cd to directory with tests results before launching this script"
  return
}

set baseurl "https://tracker.dev.opencascade.org"

if {![info exists env(MANTIS_STRING_COOKIE)]} {
  puts "Warning: environment variable MANTIS_STRING_COOKIE must be set for"
  puts "accessing OCCT bug tracker"
  set cookie ""
} else {
  set cookie "--cookie MANTIS_STRING_COOKIE=$env(MANTIS_STRING_COOKIE)"
}
                             
# Read log
set fd [open $path/tests.log r]
set log [read $fd]
close $fd

# array of ids found in names of missing files
array unset ids
array unset file_names
array unset attachment_ids
array unset attachments

# Find tests skipped due to lack of file
puts "Parsing test logs of SKIPPED tests..."
foreach line [split $log "\n"] {
  if {[regexp {CASE (\w+) (\w+) (\w+): SKIPPED \(data file is missing\)} $line res grp grd tst]} {
    set id 0
    if {[regexp {bug([0-9]+)} $tst res id]} {
      lappend ids($id) "$grp $grd $tst"
    }

    if {[catch "open $path/$grp/$grd/${tst}.log r" fd]} {
      puts "Error: cannot read log for $grp $grd $tst"
      continue
    }
    set testlog [read $fd]
    close $fd

    set start 0
    while {[regexp -start $start -indices {File (.*) could not be found} $testlog res findex]} {
      set fname [string range $testlog [lindex $findex 0] [lindex $findex 1]]
      set start [lindex $res 1]
      if {[regexp -nocase {bug([0-9]+)} $fname res idx] || 
          [regexp -nocase {OCC([0-9]+)} $fname res idx]} {
        lappend ids($idx) "$grp $grd $tst"
        # collect names of all files not found in tests associated with each issue id
        if {![info exists file_names($idx)] || [lsearch $file_names($idx) $fname] < 0} {
          lappend file_names($idx) $fname
        }
      }
      # collect names of all files not found in tests associated with each issue id
      if {[info exists ids($id)]} {
        if {![info exists file_names($id)] || [lsearch $file_names($id) $fname] < 0} {
          lappend file_names($id) $fname
        }
      }
    }
    if {$start == 0} {
      puts "Error: cannot find message on missing file in log of test $grp $grd $tst"
    }
  }
}

#puts [lsort -integer [array names ids]]
puts "Total [llength [array names ids]] issues associated with SKIPPED tests found"

# returns true if both var1 and var2 (put to lower-case) are within list vars
proc are_both_one_of {var1 var2 vars} {
  set v1 [string tolower $var1]
  set v2 [string tolower $var2]
  return [expr [lsearch $vars $v1] >= 0 && [lsearch $vars $v2] >= 0]
}

# see if issues with found Ids are accessible in OCCT Mantis bug tracker and have attached file
set candidates {}
foreach id [lsort -integer [array names ids]] {
#  if {$id < 31251} {continue}

  # get html page of the issue; repeat in cycle if url is not accessible
  # (this can be due to temporary reasons, e.g. SPES enabled)
  while 1 {
    catch "exec curl ${baseurl}/view.php?id=$id $cookie >$path/issue.html"
    set fd [open $path/issue.html r]
    set html [read $fd]
    close $fd
    if { [string length $html] > 10} break
    puts "Cannot get page of issue $id, waiting for 10 sec"
    after 10000
  }
  file delete $path/issue.html

  # skip missing or inaccessible issues
  if {[regexp -nocase {Access Denied} $html]} {
    puts "Issue $id is inaccessible for anonymous user"
    continue
  }
  if {[regexp -nocase "issue $id not found" $html]} {
    puts "Issue $id does not exist"
    continue
  }

  # check presence of attachment(s)
  if {[regexp -nocase {<a href=\"file_download[.]php} $html]} {
    puts "Issue $id is accessible and has attached file(s)"
    lappend candidates $id

    # find attached files
    set start 0
    while {[regexp -indices -start $start {<a href=\"(file_download[.]php[^\"]+)\">([^<]+)</a>} $html range furl fname]} {
      set start [lindex $range 1]
      set furl [string range $html {*}$furl]
      set fname [string range $html {*}$fname]
      # skip duplicates (each download link is usually found twice in a page)
      if {[regexp {file_id=([0-9]+)} $furl dummy fid]} {
        if {[info exists attachment_ids($fid)]} {
          if { $fname != $attachment_ids($fid) } {
            puts "Attachment with id $fid for file $fname was previously seen as file $attachment_ids($fid)"
          }
          continue
        }
        set attachment_ids($fid) $fname
      }
#      puts "$id: $furl $fname"
      lappend attachments($id) [list $furl $fname]
    }

    # download attached files; if only one file is used, and there is only one
    # attachment with the same extension, assume this attachemnt is the needed
    # file and download it with correct name;
    # all other attachments are downloaded with unique names
    set isfound 0
    foreach attach $attachments($id) {
      set aurl  [lindex $attach 0]
      set aname [lindex $attach 1]
      set aext  [file extension $aname]
      set dname ""
      if {!$isfound && [info exists file_names($id)] && 
          [llength $file_names($id)] == 1 && [llength $attachments($id)] == 1} {
        set fname $file_names($id)
        set fext [file extension $fname]
        if {$aext == $fext ||
            [are_both_one_of $fext $aext {".brep" ".rle"}] ||
            [are_both_one_of $fext $aext {".iges" ".igs"}] ||
            [are_both_one_of $fext $aext {".step" ".stp"}]} {
          set dname $fname
          set isfound 1
        }
      }
      if {$dname == ""} {
        set aid 0
        regexp {file_id=([0-9]+)} $aurl dummy aid
        set dname issue${id}_attach${aid}_$aname
      }
      if {[file exists $path/$dname] && [file size $path/$dname] > 0} {
        puts "Attachment $aname already saved in $dname"
      } else {
        puts "Downloading $aname -> $dname"
        set url "${baseurl}/[regsub {&amp;} [lindex $attach 0] {\&}]"
        catch "exec curl $url $cookie >$path/$dname"
      }
    }
  } elseif {[regexp -nocase {View issue details} $html]} {
    puts "Issue $id is accessible but has no attachments"
  } else {
    puts "Issue $id - ? logic error"
    break
  }
}

# generate summary
set outcome ""
append outcome "\nTotal [llength $candidates] candidate issues for search of data files (with relevant tests):"
foreach id $candidates {
  append outcome "\n$id: [lsort -unique $ids($id)] ->"
  if {[info exists file_names($id)]} {
    foreach fname $file_names($id) {
      append outcome " $fname"
      if {[file exists $fname]} {
        append outcome " (FOUND)"
      }
    }
  }
}
set fd [open candidates.txt w]
puts $fd $outcome
close $fd
puts "\n$outcome\nStored in global variable \$outcome and saved in file candidates.txt"
