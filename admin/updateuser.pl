use OMP::User;
use OMP::UserServer;

my $user = OMP::UserServer->getUser( "JARVISM" );

$user->email('m.jarvis1@physics.ox.ac.uk');
#$user->name("Chris J Yate");

OMP::UserServer->updateUser( $user );
