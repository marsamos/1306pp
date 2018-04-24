 program cycles
  use routines
  use f90nautyinterf

  implicit none

  integer :: nsites, &
             ievt, nevt, n_in_map, n_color, &
             hash_val1, hash_val2, hash_val3, kart_hash

  integer :: i, j, k, isite, idx
  
  real :: Rcut, dum, rnd

  real, dimension(3,3) :: bases

  integer, dimension(3) :: bases_indices

  real, allocatable :: coords(:,:), map_coords(:,:), color_cutoff(:,:), &
                       map_ordered_coords(:,:), all_prob(:), prob_M(:)
  integer, allocatable :: types(:), map_indices(:), map_types(:), &
                          connect(:,:), lab(:), color(:),&
                          global_from_sorted_color(:), sorted_from_global_color(:),&
                          site_hash(:), all_hash(:), event_nat(:), ev_site(:), ev_tag(:)

  open(unit=111,file='site.in',status='old')
  open(unit=444,file='events.in',status='old')
  open(unit=500,file='neighbor_table.dat',status='old',action='read')

 call set_random_seed()

 !!!----------------------------
 !!! set up color cutoff matrix
 !!!----------------------------
 n_color = 3
 allocate(color_cutoff(1:n_color,1:n_color))
 color_cutoff(:,:) = 0.0
 read(500,*)
 do while(.true.)
   read(500,*,end=200) i, j, dum
   color_cutoff(i,j) = dum
   color_cutoff(j,i) = dum
 end do
 !200 write(*,*) 'read neighbour', (color_cutoff(i,:),i=1,4)
 200 continue


 !!! cutoff to create a map - is not the same as color cutoff matrix, should be larger
  Rcut = 1.1
  
 !!!-------------------------
 !!! read sites
 !!!-------------------------
  call get_nsites(111,nsites) 
  allocate(coords(1:nsites,1:3))
  allocate(types(1:nsites))
  allocate(site_hash(1:nsites))
 
  call read_sites3D_new(111,nsites,types,coords)
!  do i = 1, nsites
!    write(*,*) types(i), coords(i,:)
!  end do
  



!!!------------------------------
!!!
!!! loop on all sites, get hash, store it
!!!
!!!------------------------------

 DO isite = 1, nsites
!isite = 5



   !!!---------------------------------
   !!! construct connectivity matrix from site map
   !!!---------------------------------
   call map_site(isite,Rcut,coords,types,map_coords,map_types,map_indices,n_in_map)
!write(*,*) isite,'/',nsites
!write(*,*) 'typ,coord as read'
!do i = 1, nsites
! write(*,*) map_types(i),map_coords(i,:)
!end do
   allocate(connect(1:n_in_map,1:n_in_map))
   connect(:,:) = 0
   allocate(lab(1:n_in_map))
   lab(:) = 0
   allocate(color(1:n_in_map))
   color(:) = 0
   allocate(sorted_from_global_color(1:n_in_map))
   allocate(global_from_sorted_color(1:n_in_map))


   call sort_property(n_in_map, map_types, color, global_from_sorted_color,&
                         sorted_from_global_color)
!   write(*,*)'sorted map_types',map_types
!   write(*,*) 'global_from_sorted_color',global_from_sorted_color
!   write(*,*) 'sorted_color_from_global',sorted_from_global_color
!   write(*,*) 'color is',color

   do i=1, n_in_map
      do j=i+1, n_in_map
       dum=0.0
       do k=1,3
        dum= dum+(map_coords(j,k)-map_coords(i,k))**2
       enddo
       dum=sqrt(dum)
       connect(i,j)= NINT(0.5*erfc(dum-color_cutoff(map_types(i),map_types(j))))
       connect(j,i)= NINT(0.5*erfc(dum-color_cutoff(map_types(j),map_types(i))))
   !    write(*,*) i,j,dij, connect(i,j), connect(j,i)
      enddo
   enddo
  
!   write(*,*) "connect"
!   do i=1, n_in_map
!    write(*,"(15i4)") (connect(i,j), j=1,n_in_map)
!   enddo

!   write(*,*) "lab"
   do i=1,n_in_map
     lab(i)=global_from_sorted_color(i)-1
!     write(*,*) lab(i)
   enddo
 
   !!!---------------------------
   !!! get canon, hash
   !!!---------------------------
! write(*,*) 'coords before canon11'
! do i =1,n_in_map
!  write(*,*) map_types(i), map_coords(i,:)
! end do

   hash_val1=0
   hash_val2=0
   hash_val3=0
   call c_ffnautyex1_sestic(n_in_map, connect,lab,color, hash_val1,hash_val2,hash_val3)

   kart_hash= modulo (modulo (hash_val1,104729)+ modulo(hash_val2, 15485863)+ &
           modulo(hash_val3, 882377) - 1, 1299709)+1
   write(*,*) "config hash is",isite,'/',nsites
   write(*,*) kart_hash
   
   site_hash(isite) = kart_hash


   do i=1,n_in_map
      lab(i) = lab(i) + 1
   end do


   deallocate(connect)
   deallocate(lab)
   deallocate(color)
   deallocate(sorted_from_global_color)
   deallocate(global_from_sorted_color)


 ENDDO


 !!!--------------------------------
 !!!
 !!! at this point, all site hashes are known
 !!!
 !!!--------------------------------
 
 open(unit=323,file='ordered_events.dat',status='old')
 call get_hash_prob_new(323,all_hash,all_prob,event_nat)

 write(*,*) 'events info'
 write(*,*) all_hash
 write(*,*) all_prob

 !! vector to fill probabilities
 nevt = size(all_hash)
write(*,*) 'nevt',nevt
 allocate(prob_M(1:nsites*nevt))
 allocate(ev_site(1:nsites*nevt))
 allocate(ev_tag(1:nsites*nevt))
 prob_M(:) = 0.0
 ev_site(:) = 0
 k=1
 do isite =1,nsites
   do ievt=1,nevt
     if ( all_hash(ievt)==site_hash(isite) ) then
       prob_M(k) = all_prob(ievt)
       ev_site(k) = isite
       ev_tag(k) = ievt
       k = k+1
     endif
   end do
 end do

! do i=1,size(prob_M)
!   write(*,'(A4,F5.2)') 'prob',prob_M(i)
!   write(*,'(A2,I2)') 'on',ev_site(i)
! end do

  call random_number(rnd)
  call choose_p(prob_M,size(prob_M),rnd,idx)
 write(*,*) 'chosen event',idx,'with',prob_M(idx),'which is ev@',ev_tag(idx)
 write(*,*) 'which should be at site',ev_site(idx)

!!!------------------
!!! the event is chosen at this point 'idx', on site 'ev_site(idx)'
!!!------------------
  
!!!!!!!!! get again all info of that site

   !!!---------------------------------
   !!! construct connectivity matrix from site map
   !!!---------------------------------
   call map_site(ev_site(idx),Rcut,coords,types,map_coords,map_types,map_indices,n_in_map)
!write(*,*) isite,'/',nsites
!write(*,*) 'typ,coord as read'
!do i = 1, nsites
! write(*,*) map_types(i),map_coords(i,:)
!end do
   allocate(connect(1:n_in_map,1:n_in_map))
   connect(:,:) = 0
   allocate(lab(1:n_in_map))
   lab(:) = 0
   allocate(color(1:n_in_map))
   color(:) = 0
   allocate(sorted_from_global_color(1:n_in_map))
   allocate(global_from_sorted_color(1:n_in_map))


   call sort_property(n_in_map, map_types, color, global_from_sorted_color,&
                         sorted_from_global_color)
!   write(*,*)'sorted map_types',map_types
!   write(*,*) 'global_from_sorted_color',global_from_sorted_color
!   write(*,*) 'sorted_color_from_global',sorted_from_global_color
!   write(*,*) 'color is',color

   do i=1, n_in_map
      do j=i+1, n_in_map
       dum=0.0
       do k=1,3
        dum= dum+(map_coords(j,k)-map_coords(i,k))**2
       enddo
       dum=sqrt(dum)
       connect(i,j)= NINT(0.5*erfc(dum-color_cutoff(map_types(i),map_types(j))))
       connect(j,i)= NINT(0.5*erfc(dum-color_cutoff(map_types(j),map_types(i))))
   !    write(*,*) i,j,dij, connect(i,j), connect(j,i)
      enddo
   enddo
  
!   write(*,*) "connect"
!   do i=1, n_in_map
!    write(*,"(15i4)") (connect(i,j), j=1,n_in_map)
!   enddo

!   write(*,*) "lab"
   do i=1,n_in_map
     lab(i)=global_from_sorted_color(i)-1
!     write(*,*) lab(i)
   enddo
 
   !!!---------------------------
   !!! get canon, hash
   !!!---------------------------
! write(*,*) 'coords before canon11'
! do i =1,n_in_map
!  write(*,*) map_types(i), map_coords(i,:)
! end do

   hash_val1=0
   hash_val2=0
   hash_val3=0
   call c_ffnautyex1_sestic(n_in_map, connect,lab,color, hash_val1,hash_val2,hash_val3)

   kart_hash= modulo (modulo (hash_val1,104729)+ modulo(hash_val2, 15485863)+ &
           modulo(hash_val3, 882377) - 1, 1299709)+1
!   write(*,*) "config hash is",isite,'/',nsites
   write(*,*) kart_hash
   
   do i=1,n_in_map
      lab(i) = lab(i) + 1
   end do

!   write(*,*) "canon order, canon typ, and pos in such order"
!   do i=1,n_in_map
!     write(*,*) lab(i), map_types(sorted_from_global_color(lab(i))),&
!                           map_coords(lab(i),:)
!   enddo
 
! write(*,*) 'coords before canon'
! do i =1,n_in_map
!  write(*,*) map_types(i), map_coords(i,:)
! end do
 !write(*,*) 'canon order',lab
 
   !! reorder cluster into canon 
   call sort_to_canon(n_in_map,map_coords,map_ordered_coords,lab)
! write(*,*) 'coords after canon'
! do i =1,n_in_map
!  write(*,*) map_types(i), map_ordered_coords(i,:)
! end do
 
   !! get the basis of cluster in canon order
   call find_noncollinear_vectors(n_in_map,map_ordered_coords,bases,bases_indices)
   call gram_schmidt(bases)
!   do i =1,3
!     write(*,*) bases(i,:)
!   end do
 
 
   !! replace involved vectors with final event positions
 !!!! first get final positions from ordered_events.dat

 
   !! crist_to_cart( basis found before )



   deallocate(connect)
   deallocate(lab)
   deallocate(color)
   deallocate(sorted_from_global_color)
   deallocate(global_from_sorted_color)





!write(*,*) 'coords before canon22'
!do i =1,n_in_map
! write(*,*) map_types(i), map_coords(i,:)
!end do


!   write(*,*) "canon order, canon typ, and pos in such order"
!   do i=1,n_in_map
!     write(*,*) lab(i), map_types(sorted_from_global_color(lab(i))),&
!                           map_coords(lab(i),:)
!   enddo
! 
! write(*,*) 'coords before canon'
! do i =1,n_in_map
!  write(*,*) map_types(i), map_coords(i,:)
! end do
! !write(*,*) 'canon order',lab
! 
!   !! reorder cluster into canon 
!   call sort_to_canon(n_in_map,map_coords,map_ordered_coords,lab)
! write(*,*) 'coords after canon'
! do i =1,n_in_map
!  write(*,*) map_types(i), map_ordered_coords(i,:)
! end do
! 
!   !! get the basis of cluster in canon order
! 
!   !! find possible events
! 
! ! probably this loop should end here
! 
!   !! replace involved vectors with final event positions
! 
!   !! crist_to_cart( basis found before )
! 
!   !!!---------------
!   !!! deallocate for next site
!   !!!---------------
!   deallocate(connect)
!   deallocate(lab)
!   deallocate(color)
!   deallocate(sorted_from_global_color)
!   deallocate(global_from_sorted_color)
! 

! end do
 end program cycles
