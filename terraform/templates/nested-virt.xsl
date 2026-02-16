<?xml version="1.0"?>
<!--
  XSLT transform to enable nested virtualization in libvirt domain XML.
  Ensures KVM guests can run KVM (required for OpenStack nova-compute).
-->
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="xml" omit-xml-declaration="yes" indent="yes"/>

  <!-- Identity transform: copy everything by default -->
  <xsl:template match="node()|@*">
    <xsl:copy>
      <xsl:apply-templates select="node()|@*"/>
    </xsl:copy>
  </xsl:template>

  <!-- Inject nested virt feature into CPU if not present -->
  <xsl:template match="/domain/cpu">
    <xsl:copy>
      <xsl:apply-templates select="@*|node()"/>
      <feature policy="require" name="vmx"/>
    </xsl:copy>
  </xsl:template>
</xsl:stylesheet>
