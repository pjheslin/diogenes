package XML::DOM::Lite::Serializer;
use warnings;
use strict;

use XML::DOM::Lite::Constants qw(:all);

sub new {
    my ($class, %options) = @_;
    my $self = bless { }, $class;

    $self->{_mode} = '';
    $self->{_newline} = "\n";
    $self->{_space} = " ";
    if (defined($options{'whitespace'})) {
        my $mode = $options{'whitespace'};
        if (index($mode, 'safe') >= 0) {
            $self->{_mode} = 'safe';
            $self->{_newline} = '';
            $self->{_space} = ' ';
        }
        elsif (index($mode, 'none') >= 0) {
            $self->{_none} = 'none';
            $self->{_newline} = '';
            $self->{_space} = '';
        }
    }
    return $self;
}

sub serializeToString {
    my ($self, $node, %options) = @_;
    unless (ref $self) {
        $self = __PACKAGE__->new;
    }

    $self->{_indent_level} = 0 unless defined $self->{_indent_level};
    $self->{_out} = "" unless defined $self->{_out};

    if ($node->nodeType == DOCUMENT_NODE) {
        foreach my $n (@{$node->childNodes}) {
            $self->serializeToString($n);
        }
    }

    if ($node->nodeType == ELEMENT_NODE) {
        $self->{_out} .= $self->{_newline}.$self->_mkIndent()."<".$node->tagName;
        foreach my $att (@{$node->attributes}) {
            $self->{_out} .= " $att->{nodeName}=\"".$att->{nodeValue}."\"";
        }
        if ($node->childNodes->length) {
            $self->{_out} .= ">";
            $self->{_indent_level}++;
            foreach my $n (@{$node->childNodes}) {
                $self->serializeToString($n);
            }
            $self->{_indent_level}--;
            $self->{_out} .= $self->{_newline}.$self->_mkIndent()."</".$node->tagName.">";
        } else {
            $self->{_out} .= " />";
        }
    }
    elsif ($node->nodeType == TEXT_NODE) {
        $self->{_out} .= $self->{_newline}.$self->_mkIndent().$node->nodeValue;
    }
    elsif ($node->nodeType == PROCESSING_INSTRUCTION_NODE) {
        $self->{_out} .= "<?".$node->nodeValue."?>";
    }
    return $self->{_out};
}

sub _mkIndent {
    my ($self) = @_;
    return '' if $self->{_none};
    $self->{_out} =~ m/(\s*\n\s*)$/s;
    print ":".$1.":\n" if $1;
    if ($self->{_mode} eq 'safe') {
        if ($self->{_out} =~ s/\s*\n\s*$/\n/s) {
            return ($self->{_space} x (2 * $self->{_indent_level}));
        }
        else {
            return '';
        }
    }
    return ($self->{_space} x (2 * $self->{_indent_level}));
}
1;
