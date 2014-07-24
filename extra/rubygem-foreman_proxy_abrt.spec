%global gem_name foreman_proxy_abrt

%global foreman_proxy_bundlerd_dir /usr/share/foreman-proxy/bundler.d
%global foreman_proxy_pluginconf_dir /etc/foreman-proxy/settings.d
%global spool_dir /var/spool/foreman-proxy-abrt

Name: rubygem-%{gem_name}
Version: 0.0.1
Release: 1%{?dist}
Summary: Automatic Bug Reporting Tool plugin for Foreman's smart proxy
Group: Applications/Internet
License: GPLv3
URL: http://github.com/abrt/foreman_proxy_abrt
Source0: https://fedorahosted.org/released/abrt/%{gem_name}-%{version}.gem
Requires: ruby(release)
Requires: ruby(rubygems)
Requires: rubygem(ffi)
Requires: foreman-proxy
Requires: crontabs
## does not exist in repository yet
#Requires: rubygem-satyr
BuildRequires: ruby(release)
BuildRequires: rubygems-devel
BuildRequires: ruby
BuildRequires: rubygem(ffi)
BuildRequires: rubygem(minitest)
BuildArch: noarch
Provides: rubygem(%{gem_name}) = %{version}

%description
This smart proxy plugin, together with a Foreman plugin, add the capability to
send ABRT micro-reports from your managed hosts to Foreman.

%package doc
Summary: Documentation for %{name}
Group: Documentation
Requires:%{name} = %{version}-%{release}

%description doc
Documentation for %{name}

%prep
gem unpack %{SOURCE0}
%setup -q -D -T -n  %{gem_name}-%{version}
gem spec %{SOURCE0} -l --ruby > %{gem_name}.gemspec

%build
# Create the gem as gem install only works on a gem file
gem build %{gem_name}.gemspec

# %%gem_install compiles any C extensions and installs the gem into ./%gem_dir
# by default, so that we can move it into the buildroot in %%install
%gem_install

%install
# Packaging guidelines say: Do not ship tests
rm -r .%{gem_instdir}/test .%{gem_instdir}/Rakefile
rm .%{gem_instdir}/extra/*.spec

mkdir -p %{buildroot}%{gem_dir}
cp -a .%{gem_dir}/* \
       %{buildroot}%{gem_dir}/

# executables
mkdir -p %{buildroot}%{_bindir}
cp -a .%{_bindir}/* \
       %{buildroot}%{_bindir}

# bundler file
mkdir -p %{buildroot}%{foreman_proxy_bundlerd_dir}
mv %{buildroot}%{gem_instdir}/bundler.d/abrt.rb \
   %{buildroot}%{foreman_proxy_bundlerd_dir}

# sample config
mkdir -p %{buildroot}%{foreman_proxy_pluginconf_dir}
mv %{buildroot}%{gem_instdir}/settings.d/abrt.yml.example \
   %{buildroot}%{foreman_proxy_pluginconf_dir}/

# crontab
mkdir -p %{buildroot}%{_sysconfdir}/cron.d/
mv %{buildroot}%{gem_instdir}/extra/foreman-proxy-abrt-send.cron \
   %{buildroot}%{_sysconfdir}/cron.d/%{name}

# create spool directory
mkdir -p %{buildroot}%{spool_dir}

#%check
#testrb -Ilib test

%files
%dir %{gem_instdir}
%{gem_libdir}
%exclude %{gem_cache}
%{gem_spec}
%{gem_instdir}/bin

%dir %attr(0755, foreman-proxy, foreman-proxy) %{spool_dir}
%{foreman_proxy_bundlerd_dir}/abrt.rb
%{_bindir}/smart-proxy-abrt-send
%doc %{foreman_proxy_pluginconf_dir}/abrt.yml.example
%config(noreplace) %{_sysconfdir}/cron.d/%{name}

%files doc
%{gem_docdir}
%{gem_instdir}/README
%{gem_instdir}/LICENSE

%changelog
* Tue Jul 15 2014 Martin Milata <mmilata@redhat.com> - 0.0.1-1
- Initial package
