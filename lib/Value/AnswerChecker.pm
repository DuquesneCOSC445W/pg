#############################################################
#
#  Implements the ->cmp method for Value objects.  This produces
#  an answer checker appropriate for the type of object.
#  Additional options can be passed to the checker to
#  modify its action.
#
#  The individual Value packages are modified below to add the
#  needed methods.
#

#############################################################

package Value;

#
#  Create an answer checker for the given type of object
#

sub cmp_defaults {(
  showTypeWarnings => 1,
  showEqualErrors  => 1,
  ignoreStrings    => 1,
)}

sub cmp {
  my $self = shift;
  my $ans = new AnswerEvaluator;
  $ans->ans_hash(
    type => "Value (".$self->class.")",
    correct_ans => protectHTML($self->string),
    correct_value => $self,
    $self->cmp_defaults,
    @_
  );
  $ans->install_evaluator(sub {$ans = shift; $ans->{correct_value}->cmp_parse($ans)});
  $self->{context} = $$Value::context unless defined($self->{context});
  return $ans;
}

#
#  Parse the student answer and compute its value,
#    produce the preview strings, and then compare the
#    student and professor's answers for equality.
#
sub cmp_parse {
  my $self = shift; my $ans = shift;
  #
  #  Do some setup
  #
  my $current = $$Value::context; # save it for later
  my $context = $ans->{correct_value}{context} || $current;
  Parser::Context->current(undef,$context); # change to correct answser's context
  my $flags = contextSet($context, # save old context flags for the below
    StringifyAsTeX => 0,             # reset this, just in case.
    no_parameters => 1,              # don't let students enter parameters
    showExtraParens => 1,            # make student answer painfully unambiguous
    reduceConstants => 0,            # don't combine student constants
    reduceConstantFunctions => 0,    # don't reduce constant functions
  );
  $ans->{isPreview} = $self->getPG('$inputs_ref->{previewAnswers}');
  $ans->{cmp_class} = $self->cmp_class($ans) unless $ans->{cmp_class};

  #
  #  Parse and evaluate the student answer
  #
  $ans->score(0);  # assume failure
  $ans->{student_value} = $ans->{student_formula} = Parser::Formula($ans->{student_ans});
  $ans->{student_value} = Parser::Evaluate($ans->{student_formula})
    if defined($ans->{student_formula}) && $ans->{student_formula}->isConstant;

  #
  #  If it parsed OK, save the output forms and check if it is correct
  #   otherwise report an error
  #
  if (defined $ans->{student_value}) {
    $ans->{student_value} = Value::Formula->new($ans->{student_value})
       unless Value::isValue($ans->{student_value});
    $ans->{preview_latex_string} = $ans->{student_formula}->TeX;
    $ans->{preview_text_string}  = protectHTML($ans->{student_formula}->string);
    $ans->{student_ans}          = $ans->{preview_text_string};
    $self->cmp_equal($ans);
    $self->cmp_postprocess($ans) if !$ans->{error_message};
  } else {
    $self->cmp_error($ans);
  }
  contextSet($context,%{$flags});            # restore context values
  Parser::Context->current(undef,$current);  # put back the old context
  return $ans;
}

#
#  Check if the parsed student answer equals the professor's answer
#
sub cmp_equal {
  my $self = shift; my $ans = shift;
  my $correct = $ans->{correct_value};
  my $student = $ans->{student_value};
  if ($correct->typeMatch($student,$ans)) {
    my $equal = eval {$correct == $student};
    if (defined($equal) || !$ans->{showEqualErrors}) {$ans->score(1) if $equal; return}
    $self->cmp_error($ans);
  } else {
    return if $ans->{ignoreStrings} && (!Value::isValue($student) || $student->type eq 'String');
    $ans->{ans_message} = $ans->{error_message} =
      "Your answer isn't ".lc($ans->{cmp_class}).
        " (it looks like ".lc($student->showClass).")"
	   if !$ans->{isPreview} && $ans->{showTypeWarnings} && !$ans->{error_message};
  }
}

#
#  Check if types are compatible for equality check
#
sub typeMatch {
  my $self = shift;  my $other = shift;
  return 1 unless ref($other);
  $self->type eq $other->type && $other->class ne 'Formula';
}

#
#  Class name for cmp error messages
#
sub cmp_class {
  my $self = shift; my $ans = shift;
  my $class = $self->showClass; $class =~ s/Real //;
  return $class if $class =~ m/Formula/;
  return "an Interval or Union" if $class =~ m/Interval/i;
  return $class; 
}

#
#  Student answer evaluation failed.
#  Report the error, with formatting, if possible.
#
sub cmp_error {
  my $self = shift; my $ans = shift;
  my $context = $$Value::context;
  my $message = $context->{error}{message};
  if ($context->{error}{pos}) {
    my $string = $context->{error}{string};
    my ($s,$e) = @{$context->{error}{pos}};
    $message =~ s/; see.*//;  # remove the position from the message
    $ans->{student_ans} =
       protectHTML(substr($string,0,$s)) .
       '<SPAN CLASS="parsehilight">' . 
         protectHTML(substr($string,$s,$e-$s)) .
       '</SPAN>' .
       protectHTML(substr($string,$e));
  }
  $self->cmp_Error($ans,$message);
}

#
#  Set the error message
#
sub cmp_Error {
  my $self = shift; my $ans = shift;
  return unless scalar(@_) > 0;
  $ans->score(0);
  $ans->{ans_message} = $ans->{error_message} = join("\n",@_);
}

#
#  filled in by sub-classes
#
sub cmp_postprocess {}

#
#  Get and Set values in context
#
sub contextSet {
  my $context = shift; my %set = (@_);
  my $flags = $context->{flags}; my $get = {};
  foreach my $id (keys %set) {$get->{$id} = $flags->{$id}; $flags->{$id} = $set{$id}}
  return $get;
}

#
#  Quote HTML characters
#
sub protectHTML {
    my $string = shift;
    return $string if eval ('$main::displayMode') eq 'TeX';
    $string =~ s/&/\&amp;/g;
    $string =~ s/</\&lt;/g;
    $string =~ s/>/\&gt;/g;
    $string;
}

#
#  names for numbers
#
sub NameForNumber {
  my $self = shift; my $n = shift;
  my $name =  ('zeroth','first','second','third','fourth','fifth',
               'sixth','seventh','eighth','ninth','tenth')[$n];
  $name = "$n-th" if ($n > 10);
  return $name;
}

#
#  Get a value from the safe compartment
#
sub getPG {
  my $self = shift;
#  (WeBWorK::PG::Translator::PG_restricted_eval(shift))[0];
  eval ('package main; '.shift);  # faster
}

#############################################################
#############################################################

package Value::Real;

sub cmp_defaults {(
  shift->SUPER::cmp_defaults,
  ignoreInfinity => 1,
)}

sub typeMatch {
  my $self = shift; my $other = shift; my $ans = shift;
  return 1 unless ref($other);
  return 0 if Value::isFormula($other);
  return 1 if $other->type eq 'Infinity' && $ans->{ignoreInfinity};
  $self->type eq $other->type;
}

#############################################################

package Value::Infinity;

sub cmp_class {'a Number'};

sub typeMatch {
  my $self = shift; my $other = shift; my $ans = shift;
  return 1 unless ref($other);
  return 0 if Value::isFormula($other);
  return 1 if $other->type eq 'Number';
  $self->type eq $other->type;
}

#############################################################

package Value::String;

sub cmp_defaults {(
  Value::Real->cmp_defaults,
  typeMatch => 'Value::Real',
)}

sub cmp_class {
  my $self = shift; my $ans = shift; my $typeMatch = $ans->{typeMatch};
  return 'a Word' if !Value::isValue($typeMatch) || $typeMatch->class eq 'String';
  return $typeMatch->cmp_class;
};

sub typeMatch {
  my $self = shift; my $other = shift; my $ans = shift;
  return 0 if ref($other) && Value::isFormula($other);
  my $typeMatch = $ans->{typeMatch};
  return 1 if !Value::isValue($typeMatch) || $typeMatch->class eq 'String' ||
                 $self->type eq $other->type;
  return $typeMatch->typeMatch($other,$ans);
}

#############################################################

package Value::Point;

sub cmp_defaults {(
  shift->SUPER::cmp_defaults,
  showDimensionHints => 1,
  showCoordinateHints => 1,
)}

sub typeMatch {
  my $self = shift; my $other = shift; my $ans = shift;
  return ref($other) && $other->type eq 'Point' && $other->class ne 'Formula';
}

#
#  Check for dimension mismatch and incorrect coordinates
#
sub cmp_postprocess {
  my $self = shift; my $ans = shift;
  return unless $ans->{score} == 0 && !$ans->{isPreview};
  if ($ans->{showDimensionHints} &&
      $self->length != $ans->{student_value}->length) {
    $self->cmp_Error($ans,"The dimension of your result is incorrect"); return;
  }
  if ($ans->{showCoordinateHints}) {
    my @errors;
    foreach my $i (1..$self->length) {
      push(@errors,"The ".$self->NameForNumber($i)." coordinate is incorrect")
	if ($self->{data}[$i-1] != $ans->{student_value}{data}[$i-1]);
    }
    $self->cmp_Error($ans,@errors); return;
  }
}

#############################################################

package Value::Vector;

sub cmp_defaults {(
  shift->SUPER::cmp_defaults,
  showDimensionHints => 1,
  showCoordinateHints => 1,
  promotePoints => 0,
  parallel => 0,
  sameDirection => 0,
)}

sub typeMatch {
  my $self = shift; my $other = shift; my $ans = shift;
  return 0 unless ref($other) && $other->class ne 'Formula';
  return $other->type eq 'Vector' ||
     ($ans->{promotePoints} && $other->type eq 'Point');
}

#
#  check for dimension mismatch
#        for parallel vectors, and
#        for incorrect coordinates
#
sub cmp_postprocess {
  my $self = shift; my $ans = shift;
  return unless $ans->{score} == 0;
  if (!$ans->{isPreview} && $ans->{showDimensionHints} &&
      $self->length != $ans->{student_value}->length) {
    $self->cmp_Error($ans,"The dimension of your result is incorrect"); return;
  }
 if ($ans->{parallel} &&
     $self->isParallel($ans->{student_value},$ans->{sameDirection})) {
   $ans->score(1); return;
 }
  if (!$ans->{isPreview} && $ans->{showCoordinateHints}) {
    my @errors;
    foreach my $i (1..$self->length) {
      push(@errors,"The ".$self->NameForNumber($i)." coordinate is incorrect")
	if ($self->{data}[$i-1] != $ans->{student_value}{data}[$i-1]);
    }
    $self->cmp_Error($ans,@errors); return;
  }
}



#############################################################

package Value::Matrix;

sub cmp_defaults {(
  shiftf->SUPER::cmp_defaults,
  showDimensionHints => 1,
  showEqualErrors => 0,
)}

sub typeMatch {
  my $self = shift; my $other = shift; my $ans = shift;
  return 0 unless ref($other) && $other->class ne 'Formula';
  return $other->type eq 'Matrix' ||
    ($other->type =~ m/^(Point|list)$/ &&
     $other->{open}.$other->{close} eq $self->{open}.$self->{close});
}

sub cmp_postprocess {
  my $self = shift; my $ans = shift;
  return unless $ans->{score} == 0 &&
    !$ans->{isPreview} && $ans->{showDimensionHints};
  my @d1 = $self->dimensions; my @d2 = $ans->{student_value}->dimensions;
  if (scalar(@d1) != scalar(@d2)) {
    $self->cmp_Error($ans,"Matrix dimension is not correct");
    return;
  } else {
    foreach my $i (0..scalar(@d1)-1) {
      if ($d1[$i] != $d2[$i]) {
	$self->cmp_Error($ans,"Matrix dimension is not correct");
	return;
      }
    }
  }
}

#############################################################

package Value::Interval;

sub cmp_defaults {(
  shift->SUPER::cmp_defaults,
  showEndpointHints => 1,
  showEndTypeHints => 1,
)}

sub typeMatch {
  my $self = shift; my $other = shift;
  return 0 unless ref($other) && $other->class ne 'Formula';
  return $other->length == 2 &&
         ($other->{open} eq '(' || $other->{open} eq '[') &&
         ($other->{close} eq ')' || $other->{close} eq ']')
	   if $other->type =~ m/^(Point|List)$/;
  $other->type =~ m/^(Interval|Union)$/;
}

#
#  Check for wrong enpoints and wrong type of endpoints
#
sub cmp_postprocess {
  my $self = shift; my $ans = shift;
  return unless $ans->{score} == 0 && !$ans->{isPreview};
  my $other = $ans->{student_value};
  return unless $other->class eq 'Interval';
  my @errors;
  if ($ans->{showEndpointHints}) {
    push(@errors,"Your left endpoint is incorrect")
      if ($self->{data}[0] != $other->{data}[0]);
    push(@errors,"Your right endpoint is incorrect")
      if ($self->{data}[1] != $other->{data}[1]);
  }
  if (scalar(@errors) == 0 && $ans->{showEndTypeHints}) {
    push(@errors,"The type of interval is incorrect")
      if ($self->{open}.$self->{close} ne $other->{open}.$other->{close});
  }
  $self->cmp_Error($ans,@errors);
}

#############################################################

package Value::Union;

sub typeMatch {
  my $self = shift; my $other = shift;
  return 0 unless ref($other) && $other->class ne 'Formula';
  return $other->length == 2 &&
         ($other->{open} eq '(' || $other->{open} eq '[') &&
         ($other->{close} eq ')' || $other->{close} eq ']')
	   if $other->type =~ m/^(Point|List)$/;
  $other->type =~ m/^(Interval|Union)/;
}

#
#  Use the List checker for unions, in order to get
#  partial credit.  Set the various types for error
#  messages.
#
sub cmp_defaults {(
  Value::List::cmp_defaults(@_),
  typeMatch => 'Value::Interval',
  list_type => 'an interval or union',
  entry_type => 'an interval',
)}

sub cmp_equal {Value::List::cmp_equal(@_)}

#############################################################

package Value::List;

sub cmp_defaults {
  my $self = shift;
  return (
    Value::Real->cmp_defaults,
    showHints => undef,
    showLengthHints => undef,
    showParenHints => undef,
    partialCredit => undef,
    ordered => 0,
    entry_type => undef,
    list_type => undef,
    typeMatch => Value::makeValue($self->{data}[0]),
    requireParenMatch => 1,
    removeParens => 1,
   );
}

#
#  Match anything but formulas
#
sub typeMatch {return !ref($other) || $other->class ne 'Formula'}

#
#  Handle removal of outermost parens in correct answer.
#
sub cmp {
  my $self = shift;
  my $cmp = $self->SUPER::cmp(@_);
  if ($cmp->{rh_ans}{removeParens}) {
    $self->{open} = $self->{close} = '';
    $cmp->ans_hash(correct_ans => $self->stringify);
  }
  return $cmp;
}

sub cmp_equal {
  my $self = shift; my $ans = shift;
  $ans->{showPartialCorrectAnswers} = $self->getPG('$showPartialCorrectAnswers');

  #
  #  get the paramaters
  #
  my $showTypeWarnings = $ans->{showTypeWarnings};
  my $showHints        = getOption($ans,'showHints');
  my $showLengthHints  = getOption($ans,'showLengthHints');
  my $showParenHints   = getOption($ans,'showLengthHints');
  my $partialCredit    = getOption($ans,'partialCredit');
  my $ordered = $ans->{ordered};
  my $requireParenMatch = $ans->{requireParenMatch};
  my $typeMatch = $ans->{typeMatch};
  my $value     = $ans->{entry_type};
  my $ltype     = $ans->{list_type} || lc($self->type);

  $value = (Value::isValue($typeMatch)? lc($typeMatch->cmp_class): 'value')
    unless defined($value);
  $value =~ s/(real|complex) //; $ans->{cmp_class} = $value;
  $value =~ s/^an? //; $value = 'formula' if $value =~ m/formula/;
  $ltype =~ s/^an? //;
  $showTypeWarnings = $showHints = $showLengthHints = 0 if $ans->{isPreview};

  #
  #  Get the lists of correct and student answers
  #   (split formulas that return lists or unions)
  #
  my @correct = (); my ($cOpen,$cClose);
  if ($self->class ne 'Formula') {
    @correct = $self->value;
    $cOpen = $ans->{correct_value}{open}; $cClose = $ans->{correct_value}{close};
  } else {
    @correct = Value::List->splitFormula($self,$ans);
    $cOpen = $self->{tree}{open}; $cClose = $self->{tree}{close};
  }
  my $student = $ans->{student_value}; my @student = ($student);
  my ($sOpen,$sClose) = ('','');
  if (Value::isFormula($student) && $student->type eq $self->type) {
    @student = Value::List->splitFormula($student,$ans);
    $sOpen = $student->{tree}{open}; $sClose = $student->{tree}{close};
  } elsif ($student->class ne 'Formula' && $student->class eq $self->type) {
    @student = @{$student->{data}};
    $sOpen = $student->{open}; $sClose = $student->{close};
  }
  return if $ans->{split_error};
  #
  #  Check for parenthesis match
  #
  if ($requireParenMatch && ($sOpen ne $cOpen || $sClose ne $cClose)) {
    if ($showParenHints && !($ans->{ignoreStrings} && $student->type eq 'String')) {
      my $message = "The parentheses for your $ltype ";
      if (($cOpen || $cClose) && ($sOpen || $sClose))
                                {$message .= "are of the wrong type"}
      elsif ($sOpen || $sClose) {$message .= "should be removed"}
      else                      {$message .= "are missing"}
      $self->cmp_Error($ans,$message) unless $ans->{isPreview};
    }
    return;
  }
  #
  #  Check for empty lists
  #
  if (scalar(@correct) == 0 && scalar(@student) == 0) {$ans->score(1); return}  

  #
  #  Initialize the score
  #
  my $M = scalar(@correct);
  my $m = scalar(@student);
  my $maxscore = ($m > $M)? $m : $M;
  my $score = 0; my @errors; my $i = 0;

  #
  #  Loop through student answers looking for correct ones
  #
  ENTRY: foreach my $entry (@student) {
    $i++;
    $entry = Value::makeValue($entry);
    $entry = Value::Formula->new($entry) if !Value::isValue($entry);
    if ($ordered) {
      if (eval {shift(@correct) == $entry}) {$score++; next ENTRY}
    } else {
      foreach my $k (0..$#correct) {
	if (eval {$correct[$k] == $entry}) {
	  splice(@correct,$k,1);
	  $score++; next ENTRY;
	}
      }
    }
    #
    #  Give messages about incorrect answers
    #
    my $nth = ''; my $answer = 'answer';
    my $class = $ans->{list_type} || $self->cmp_class;
    if (scalar(@student) > 1) {
      $nth = ' '.$self->NameForNumber($i);
      $class = $ans->{cmp_class};
      $answer = 'value';
    }
    if ($showTypeWarnings && !$typeMatch->typeMatch($entry,$ans) &&
	!($ans->{ignoreStrings} && $entry->class eq 'String')) {
      push(@errors,"Your$nth $answer isn't ".lc($class).
	   " (it looks like ".lc($entry->showClass).")");
    } elsif ($showHints && $m > 1) {
      push(@errors,"Your$nth $value is incorrect");
    }
  }

  #
  #  Give hints about extra or missing answsers
  #
  if ($showLengthHints) {
    $value =~ s/ or /s or /; # fix "interval or union"
    push(@errors,"There should be more ${value}s in your $ltype")
      if ($score == $m && scalar(@correct) > 0);
    push(@errors,"There should be fewer ${value}s in your $ltype")
      if ($score < $maxscore && $score == $M && !$showHints);
  }

  #
  #  Finalize the score
  #
  $score = 0 if ($score != $maxscore && !$partialCredit);
  $ans->score($score/$maxscore);
  push(@errors,"Score = $ans->{score}") if $ans->{debug};
  $ans->{error_message} = $ans->{ans_message} = join("\n",@errors);
}

#
#  Split a formula that is a list or union into a
#    list of formulas (or Value objects).
#
sub splitFormula {
  my $self = shift; my $formula = shift; my $ans = shift;
  my @formula; my @entries;
  if ($formula->type eq 'List') {@entries = @{$formula->{tree}{coords}}}
      else {@entries = $formula->{tree}->makeUnion}
  foreach my $entry (@entries) {
    my $v = Parser::Formula($entry);
       $v = Parser::Evaluate($v) if (defined($v) && $v->isConstant);
    push(@formula,$v);
    #
    #  There shouldn't be an error evaluating the formula,
    #    but you never know...
    #
    if (!defined($v)) {$ans->{split_error} = 1; $self->cmp_error; return}
  }
  return @formula;
}

#
#  Return the value if it is defined, otherwise use a default
#
sub getOption {
  my $ans = shift; my $name = shift; 
  my $value = $ans->{$name};
  return $value if defined($value);
  return $ans->{showPartialCorrectAnswers};
}

#############################################################

package Value::Formula;

sub cmp_defaults {
  my $self = shift;

  return (
    Value::Union::cmp_defaults($self,@_),
    typeMatch => Value::Formula->new("(1,2]"),
  ) if $self->type eq 'Union';

  my $type = $self->type;
  $type = ($self->isComplex)? 'Complex': 'Real' if $type eq 'Number';
  $type = 'Value::'.$type.'::';

  return (&{$type.'cmp_defaults'}($self,@_), upToConstant => 0)
    if defined(%$type) && $self->type ne 'List';

  return (
    Value::List::cmp_defaults($self,@_),
    removeParens => $self->{autoFormula},
    typeMatch => Value::Formula->new(($self->createRandomPoints(1))[1]->[0]{data}[0]),
  );
}

#
#  Get the types from the values of the formulas
#     and compare those.
#
sub typeMatch {
  my $self = shift; my $other = shift; my $ans = shift;
  return 1 if $self->type eq $other->type;
  my $typeMatch = ($self->createRandomPoints(1))[1]->[0];
  $other = eval {($other->createRandomPoints(1))[1]->[0]} if Value::isFormula($other);
  return 1 unless defined($other); # can't really tell, so don't report type mismatch
  $typeMatch->typeMatch($other,$ans);
}

#
#  Handle removal of outermost parens in a list.
#
sub cmp {
  my $self = shift;
  my $cmp = $self->SUPER::cmp(@_);
  if ($cmp->{rh_ans}{removeParens} && $self->type eq 'List') {
    $self->{tree}{open} = $self->{tree}{close} = '';
    $cmp->ans_hash(correct_ans => $self->stringify);
  }
  if ($cmp->{rh_ans}{upToConstant}) {
    my $current = Parser::Context->current();
    my $context = $self->{context} = $self->{context}->copy;
    Parser::Context->current(undef,$context);
    $context->{_variables}->{pattern} = $context->{_variables}->{namePattern} =
      'C0|' . $context->{_variables}->{pattern};
    $context->update; $context->variables->add('C0' => 'Parameter');
    $cmp->ans_hash(correct_value => Value::Formula->new('C0')+$self);
    Parser::Context->current(undef,$current);
  }
  return $cmp;
}

sub cmp_equal {
  my $self = shift; my $ans = shift;
  #
  #  Get the problem's seed
  #
  $self->{context}->flags->set(
    random_seed => $self->getPG('$PG_original_problemSeed')
  );

  #
  #  Use the list checker if the formula is a list or union
  #    Otherwise use the normal checker
  #
  if ($self->type =~ m/^(List|Union)$/) {
    Value::List::cmp_equal($self,$ans);
  } else {
    $self->SUPER::cmp_equal($ans);
  }
}

sub cmp_postprocess {
  my $self = shift; my $ans = shift;
  return unless $ans->{score} == 0 && !$ans->{isPreview};
  return if $ans->{ans_message} || !$ans->{showDimensionHints};
  my $other = $ans->{student_value};
  return unless $other->type =~ m/^(Point|Vector|Matrix)$/;
  return unless $self->type  =~ m/^(Point|Vector|Matrix)$/;
  return if Parser::Item::typeMatch($self->typeRef,$other->typeRef);
  $self->cmp_Error($ans,"The dimension of your result is incorrect");
}

#############################################################

1;
